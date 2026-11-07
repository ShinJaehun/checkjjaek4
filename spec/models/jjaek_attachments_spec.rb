require "rails_helper"

RSpec.describe Jjaek, "book attachments", type: :model do
  let(:user) { User.create!(name: "Reader", email: "attachments@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "First") }
  let(:other_book) { Book.create!(title: "Second") }
  let(:jjaek) { create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: user, content: "Original") }

  it "accepts optional ordered books without a bookshelf, including profile conversations" do
    target = User.create!(name: "Friend", email: "attachment-friend@example.com", password: "password123!")
    post = user.jjaeks.create!(target_user: target, content: "Conversation")
    expect(post.update_attached_books(books: [ other_book, book ])).to be(true)
    expect(post.reload.attached_books).to eq([ other_book, book ])
    expect(user.bookshelf_entries).to be_empty
  end

  it "distinguishes omitted, invalid, and explicitly empty attachments" do
    expect(jjaek.update_attached_books(attributes: { content: "Edited" })).to be(true)
    expect(jjaek.reload.attached_books).to eq([ book ])
    [ nil, "", [ book.id ], [ nil ], [ book, book ] ].each do |invalid|
      expect(jjaek.update_attached_books(books: invalid)).to be(false)
      expect(jjaek.reload.attached_books).to eq([ book ])
    end
    expect(jjaek.update_attached_books(books: [])).to be(true)
    expect(jjaek.reload.attributes).not_to have_key("book_id")
    expect(jjaek.legacy_source_kind).to be_nil

    expect(jjaek.attached_books).to be_empty
    jjaek.update!(content: "Still empty")
    expect(jjaek.reload.attached_books).to be_empty
  end

  it "keeps identical ordered links and applies a changed selection order" do
    post = create_jjaek_with_books(user:, books: [ book, other_book ], content: "Ordered books")
    original_links = post.jjaek_book_attachments.map(&:attributes)

    expect(post.update_attached_books(books: [ book, other_book ], attributes: { content: "Edited" })).to be(true)
    expect(post.reload.jjaek_book_attachments.map(&:attributes)).to eq(original_links)

    expect(post.update_attached_books(books: [ other_book, book ])).to be(true)
    expect(post.reload.attached_books).to eq([ other_book, book ])
  end

  it "rolls back books, links, content, tags and visibility on a failed replacement" do
    jjaek.update!(content: "Original #tag")
    fresh_book = Book.new(title: "Must roll back")
    expect(jjaek.update_attached_books(books: [ fresh_book ], attributes: { content: "", visibility: :private_jjaek })).to be(false)
    expect(jjaek.reload).to have_attributes(content: "Original #tag", visibility: "public_jjaek")
    expect(jjaek.attached_books).to eq([ book ])
    expect(jjaek.tags.pluck(:name)).to eq([ "tag" ])
    expect(Book.exists?(title: fresh_book.title)).to be(false)
  end

  it "allows five books and rejects six atomically" do
    books = 6.times.map { |i| Book.create!(title: "Book #{i}") }
    expect(jjaek.update_attached_books(books: books.first(5))).to be(true)
    expect(jjaek.update_attached_books(books: books)).to be(false)
    expect(jjaek.reload.attached_books).to eq(books.first(5))
  end

  it "rejects new requote books but preserves historical books and deleted-source edits" do
    source = user.jjaeks.create!(content: "Source")
    expect(build_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: user, quoted_jjaek: source, content: "New quote")).not_to be_valid
    quote = user.jjaeks.create!(quoted_jjaek: source, content: "Historical quote")
    quote.update_columns(legacy_source_kind: "book")
    JjaekBookAttachment.insert_all!([ { jjaek_id: quote.id, book_id: book.id, position: 0, visible_on_tombstone: true } ])
    expect(quote.reload.update_attached_books(books: [ book ], attributes: { content: "Edited" })).to be(true)
    expect(quote.update_attached_books(books: [ book, other_book ])).to be(false)
    expect(quote.reload.attached_books).to eq([ book ])
    source.destroy!
    expect(quote.reload.update!(content: "After deletion")).to be(true)
    expect(quote.update_attached_books(books: [ other_book ])).to be(false)
    expect(quote.reload.attached_books).to eq([ book ])
  end
end
