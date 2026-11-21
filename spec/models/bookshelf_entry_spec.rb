require "rails_helper"

RSpec.describe BookshelfEntry, type: :model do
  let(:user) { User.create!(name: "Reader", email: "visibility@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "북짹", authors_text: "저자") }

  it "creates a reading record for a new placement" do
    entry = described_class.create!(user:, book:)

    expect(entry.reload.user_book).to have_attributes(user: user, book: book, status: nil)
  end

  it "does not allow duplicate shelf entries for the same user and book" do
    described_class.create!(user:, book:)
    duplicate = described_class.new(user:, book:)

    expect(duplicate).not_to be_valid
  end

  it "assigns the user's default bookshelf" do
    entry = described_class.create!(user:, book:)

    expect(entry.bookshelf).to eq(user.default_bookshelf)
  end

  it "assigns the next position in the bookshelf" do
    described_class.create!(user:, book:)
    next_book = Book.create!(title: "다음 책", authors_text: "저자")

    entry = described_class.create!(user:, book: next_book)

    expect(entry.position).to eq(2)
  end

  it "orders manual profile sorting by position" do
    first_book = Book.create!(title: "첫 책", authors_text: "저자")
    second_book = Book.create!(title: "둘째 책", authors_text: "저자")
    second = described_class.create!(user:, book: second_book, position: 2)
    first = described_class.create!(user:, book: first_book, position: 1)

    expect(described_class.profile_sorted("manual")).to eq([ first, second ])
  end

  it "moves an entry to the last position in the target bookshelf" do
    entry = described_class.create!(user:, book:)
    target_bookshelf = user.bookshelves.create!(name: "이동 대상")
    target_book = Book.create!(title: "대상 책장 책", authors_text: "저자")
    described_class.create!(user:, book: target_book, bookshelf: target_bookshelf)

    entry.move_to_bookshelf!(target_bookshelf)

    expect(entry.reload.bookshelf).to eq(target_bookshelf)
    expect(entry.position).to eq(2)
  end

  it "requires the entry user and bookshelf owner to match" do
    other_user = User.create!(name: "Other", email: "other-entry@example.com", password: "password123!", password_confirmation: "password123!")
    entry = described_class.new(user:, book:, bookshelf: other_user.default_bookshelf)

    expect(entry).not_to be_valid
    expect(entry.errors[:bookshelf]).to be_present
  end

  it "requires the reading record to match the placement owner and book" do
    other = User.create!(name: "Other", email: "other-user-book@example.com", password: "password123!")
    other_record = other.user_books.create!(book:)
    entry = described_class.new(user:, book:, user_book: other_record)

    expect(entry).not_to be_valid
    expect(entry.errors.of_kind?(:user_book, :invalid)).to be(true)
  end

  it "rejects a different owner or book at the database even when validations are bypassed" do
    entry = described_class.create!(user:, book:)
    other = User.create!(name: "Other", email: "other-user-book@example.com", password: "password123!")
    other_owner_record = other.user_books.create!(book:)
    other_book_record = user.user_books.create!(book: Book.create!(title: "Other book"))

    [ other_owner_record, other_book_record ].each do |record|
      expect {
        described_class.transaction(requires_new: true) do
          entry.update_columns(user_book_id: record.id)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_bookshelf_entries_matching_user_book/)
    end

    expect(entry.reload.user_book).to have_attributes(user:, book:)
  end
end
