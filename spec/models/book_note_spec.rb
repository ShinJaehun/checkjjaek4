require "rails_helper"

RSpec.describe BookNote, type: :model do
  let(:user) { User.create!(name: "Reader", email: "book-note-model@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "A book to reread") }
  let(:entry) { user.bookshelf_entries.create!(book:) }
  let(:user_book) { entry.user_book }

  it "stores multiple notes and counts plain text independently of HTML markup" do
    note = user_book.book_notes.create!(body: "<strong>#{'&amp;' * 10_000}</strong>")
    user_book.book_notes.create!(title: "Another thought", body: "Page 50")

    expect(user_book.book_notes.count).to eq(2)
    expect(note.reload.title).to be_nil
    expect(note.body.to_plain_text).to eq("&" * 10_000)
    expect(note.update(body: "<em>#{'가' * 10_001}</em>")).to be(false)
    expect(note.errors.of_kind?(:body, :too_long)).to be(true)
  end

  it "rejects blank text, empty list items and quotations, and invisible whitespace" do
    [ nil, "<p><strong><br></strong></p>", "<ul><li><br></li></ul>",
      "<blockquote>&nbsp;</blockquote>", "<div>&#8203; </div>" ].each do |body|
      note = user_book.book_notes.build(body:)

      expect(note).not_to be_valid
      expect(note.errors.of_kind?(:body, :blank)).to be(true)
    end
  end

  it "rejects a submitted Action Text attachment or raw media even with visible text" do
    [ '<action-text-attachment sgid="untrusted"></action-text-attachment>',
      '<figure data-trix-attachment=\'{"contentType":"image/png","url":"https://example.test/cover.png"}\'></figure>',
      '<figure data-trix-attachment="[]"></figure>',
      '<img src="https://example.test/cover.png">' ].each do |attachment|
      note = user_book.book_notes.build(body: "<p>Some text</p>#{attachment}")

      expect(note.save).to be(false)
      expect(note.errors.of_kind?(:body, :attachments_not_allowed)).to be(true)
    end
  end

  it "cleans up the note and its Action Text record when account withdrawal removes the UserBook" do
    note = user_book.book_notes.create!(body: "Private reading record")
    rich_text_id = note.rich_text_body.id

    Users::WithdrawAccount.new(user, current_password: "password123!").call!

    expect(UserBook.exists?(user_book.id)).to be(false)
    expect(described_class.exists?(note.id)).to be(false)
    expect(ActionText::RichText.exists?(rich_text_id)).to be(false)
  end
end
