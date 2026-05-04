require "rails_helper"

RSpec.describe Bookshelf, type: :model do
  let(:user) { User.create!(name: "Shelf Owner", email: "shelf-owner@example.com", password: "password123!", password_confirmation: "password123!") }

  it "requires a name" do
    bookshelf = described_class.new(user:, name: nil)

    expect(bookshelf).not_to be_valid
    expect(bookshelf.errors[:name]).to be_present
  end

  it "defaults visibility to public" do
    bookshelf = described_class.create!(user:, name: "Public Shelf")

    expect(bookshelf.visibility).to eq("public")
    expect(bookshelf).to be_visibility_public
  end

  it "does not allow duplicate names for the same user" do
    described_class.create!(user:, name: "Same Name")
    duplicate = described_class.new(user:, name: "Same Name")

    expect(duplicate).not_to be_valid
  end

  it "does not allow more than twenty bookshelves per user" do
    19.times do |index|
      user.bookshelves.create!(name: "Shelf #{index}")
    end

    bookshelf = user.bookshelves.build(name: "One Too Many")

    expect(bookshelf).not_to be_valid
    expect(bookshelf.errors[:base]).to be_present
  end

  it "does not allow more than one default bookshelf per user" do
    duplicate = described_class.new(user:, name: "Another Default", is_default: true)

    expect(duplicate).not_to be_valid
  end

  it "allows book_friends visibility" do
    bookshelf = described_class.new(user:, name: "Friends Shelf", visibility: :book_friends)

    expect(bookshelf).to be_valid
  end

  it "allows private visibility with prefixed enum methods" do
    bookshelf = described_class.new(user:, name: "Private Shelf", visibility: :private)

    expect(bookshelf).to be_valid
    expect(bookshelf).to be_visibility_private
  end

  it "does not destroy entries when destroying a bookshelf with entries" do
    book = Book.create!(title: "Shelf Entry Book", authors_text: "Author")
    bookshelf = user.bookshelves.create!(name: "Entry Shelf")
    entry = user.bookshelf_entries.create!(book:, bookshelf:)

    expect(bookshelf.destroy).to be(false)
    expect(bookshelf.errors[:base]).to be_present
    expect(described_class.exists?(bookshelf.id)).to be(true)
    expect(BookshelfEntry.exists?(entry.id)).to be(true)
  end

  it "does not allow destroying the default bookshelf directly" do
    bookshelf = user.default_bookshelf

    expect(bookshelf.destroy).to be(false)
    expect(bookshelf.errors[:base]).to be_present
    expect(described_class.exists?(bookshelf.id)).to be(true)
  end

  it "does not allow changing the default bookshelf name" do
    bookshelf = user.default_bookshelf
    bookshelf.name = "다른 이름"

    expect(bookshelf).not_to be_valid
    expect(bookshelf.errors[:name]).to be_present
  end

  it "does not allow changing the default bookshelf visibility" do
    bookshelf = user.default_bookshelf
    bookshelf.visibility = :private

    expect(bookshelf).not_to be_valid
    expect(bookshelf.errors[:visibility]).to be_present
  end

  it "does not allow changing the default bookshelf flag to false" do
    bookshelf = user.default_bookshelf
    bookshelf.is_default = false

    expect(bookshelf).not_to be_valid
    expect(bookshelf.errors[:is_default]).to be_present
  end

  it "allows changing a non-default bookshelf name" do
    bookshelf = user.bookshelves.create!(name: "Old Shelf")
    bookshelf.name = "New Shelf"

    expect(bookshelf).to be_valid
  end
end
