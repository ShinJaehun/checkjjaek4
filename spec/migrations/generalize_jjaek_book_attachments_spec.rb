require "rails_helper"

RSpec.describe GeneralizeJjaekBookAttachments do
  around { |example| with_historical_jjaek_schema { |tables| @tables = tables; example.run } }
  let(:migration) { described_class.new }
  let(:posts) { @tables.fetch(:jjaeks) }
  let(:links) { @tables.fetch(:jjaek_recommendations) }
  let(:book) { @tables.fetch(:books).create!(title: "Legacy book") }

  it "preserves IDs, timestamps, relations and ordered recommendation links when repeated" do
    legacy = posts.create!(user_id: 1, content: "Legacy", book_id: book.id)
    comment = @tables.fetch(:comments).create!(user_id: 1, jjaek_id: legacy.id, content: "Comment")
    like = @tables.fetch(:likes).create!(user_id: 1, jjaek_id: legacy.id)
    quote = posts.create!(user_id: 1, content: "Quote", quoted_jjaek_id: legacy.id)
    notification = @tables.fetch(:notifications).create!(recipient_id: 1, actor_id: 1, notifiable_id: legacy.id, notifiable_type: "Jjaek", action: 3)
    original_relations = [comment, like, quote, notification].map { |record| record.attributes.except("book_attachments_migrated") }
    recommended = posts.create!(user_id: 1, recommendation: true, content: "Recommended")
    other = @tables.fetch(:books).create!(title: "Other")
    [other, book].each_with_index { |item, position| links.create!(jjaek_id: recommended.id, book_id: item.id, position:) }
    original_links = links.where(jjaek_id: recommended.id).order(:position).map(&:attributes)
    original_attributes = legacy.attributes.except("book_attachments_migrated")

    2.times { migration.backfill_book_attachments }

    expect(legacy.reload.attributes.except("book_attachments_migrated")).to eq(original_attributes)
    expect(links.where(jjaek_id: legacy.id).pluck(:book_id)).to eq([book.id])
    expect([comment, like, quote, notification].map { |record| record.reload.attributes.except("book_attachments_migrated") }).to eq(original_relations)
    expect(quote.book_attachments_migrated).to be(true)
    expect(links.where(jjaek_id: recommended.id).order(:position).map(&:attributes)).to eq(original_links)
    links.where(jjaek_id: legacy.id).delete_all
    migration.backfill_book_attachments
    expect(links.where(jjaek_id: legacy.id)).to be_empty
  end

  it "fails without partial conversion on conflicting data and can be retried after correction" do
    legacy = posts.create!(user_id: 1, content: "Legacy", book_id: book.id)
    conflict = posts.create!(user_id: 1, content: "Conflict", book_id: book.id)
    other = @tables.fetch(:books).create!(title: "Conflicting")
    link = links.create!(jjaek_id: conflict.id, book_id: other.id, position: 0)
    original = link.attributes
    expect { migration.backfill_book_attachments }.to raise_error(/Conflicting book attachments/)
    expect(legacy.reload.book_attachments_migrated).to be(false)
    expect(links.where(jjaek_id: legacy.id)).to be_empty
    expect(link.reload.attributes).to eq(original)
    conflict.update_columns(book_id: nil)
    migration.backfill_book_attachments
    expect(links.where(jjaek_id: legacy.id).pluck(:book_id)).to eq([book.id])
    expect(conflict.reload.book_attachments_migrated).to be(true)
  end

  it "rejects excessive historical lists without truncating their links" do
    post = posts.create!(user_id: 1, content: "Historical")
    6.times do |position|
      item = @tables.fetch(:books).create!(title: "Book #{position}")
      links.create!(jjaek_id: post.id, book_id: item.id, position:)
    end
    expect { migration.backfill_book_attachments }.to raise_error(/Conflicting book attachments/)
    expect(post.reload.book_attachments_migrated).to be(false)
    expect(links.where(jjaek_id: post.id).count).to eq(6)
  end
end
