require "rails_helper"
require Rails.root.join("db/migrate/20261106000000_generalize_jjaek_book_attachments")

RSpec.describe GeneralizeJjaekBookAttachments do
  let(:migration) { described_class.new }
  let(:user) { User.create!(name: "Reader", email: "backfill-books@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Legacy book") }

  around do |example|
    migration.suppress_messages { example.run }
  end

  it "preserves IDs, timestamps, relations and ordered recommendation links when repeated" do
    legacy = user.jjaeks.create!(content: "Legacy")
    legacy.update_columns(book_id: book.id, book_attachments_migrated: false)
    comment = legacy.comments.create!(user:, content: "Comment")
    like = legacy.likes.create!(user:)
    quote = user.jjaeks.create!(content: "Quote", quoted_jjaek: legacy)
    notification = Notification.create!(recipient: user, actor: user, notifiable: legacy, action: :requote_created)
    original_notification = notification.attributes
    recommended = user.jjaeks.create!(recommendation: true, content: "Recommended")
    recommended.update_recommendation_books(books: [Book.create!(title: "Other"), book], attributes: {})
    recommended.update_columns(book_attachments_migrated: false)
    original_links = recommended.jjaek_recommendations.reload.map(&:attributes)
    original_attributes = legacy.attributes.except("book_attachments_migrated")

    2.times { migration.backfill_book_attachments }

    expect(legacy.reload.attributes.except("book_attachments_migrated")).to eq(original_attributes)
    expect(legacy.attached_books).to eq([book])
    expect(legacy.comments).to include(comment)
    expect(legacy.likes).to include(like)
    expect(quote.reload.quoted_jjaek_id).to eq(legacy.id)
    expect(notification.reload.attributes).to eq(original_notification)
    expect(recommended.jjaek_recommendations.reload.map(&:attributes)).to eq(original_links)

    legacy.update_attached_books(books: [])
    legacy.update_columns(book_id: book.id) # Even a retained stale legacy field cannot resurrect a book.
    migration.backfill_book_attachments
    expect(legacy.reload.attached_books).to be_empty
  end

  it "fails without partial conversion on conflicting data and can be retried after correction" do
    legacy = user.jjaeks.create!(content: "Legacy")
    legacy.update_columns(book_id: book.id, book_attachments_migrated: false)
    conflict = user.jjaeks.create!(content: "Conflict")
    conflict.update_columns(book_id: book.id, book_attachments_migrated: false)
    link = JjaekRecommendation.create!(jjaek: conflict, book: Book.create!(title: "Conflicting"), position: 0)

    expect { migration.backfill_book_attachments }.to raise_error(/Conflicting book attachments/)
    expect(legacy.reload).not_to be_book_attachments_migrated
    expect(legacy.jjaek_recommendations).to be_empty
    expect(link.reload.book.title).to eq("Conflicting")

    conflict.update_columns(book_id: nil)
    migration.backfill_book_attachments
    expect(legacy.reload.attached_books).to eq([book])
    expect(conflict.reload).to be_book_attachments_migrated
  end

  it "rejects excessive historical lists without truncating their links" do
    post = user.jjaeks.create!(content: "Historical")
    post.update_columns(book_attachments_migrated: false)
    rows = 6.times.map do |position|
      { jjaek_id: post.id, book_id: Book.create!(title: "Book #{position}").id, position: }
    end
    JjaekRecommendation.insert_all!(rows)
    expect { migration.backfill_book_attachments }.to raise_error(/Conflicting book attachments/)
    expect(post.reload).not_to be_book_attachments_migrated
    expect(post.jjaek_recommendations.count).to eq(6)
  end
end
