require "rails_helper"

RSpec.describe User, type: :model do
  it "creates a default bookshelf when the user is created" do
    user = described_class.create!(
      name: "Default Shelf User",
      email: "default-shelf-user@example.com",
      password: "password123!",
      password_confirmation: "password123!"
    )

    expect(user.bookshelves.count).to eq(1)
    expect(user.default_bookshelf).to be_is_default
  end

  it "names the default bookshelf 내 책장" do
    user = described_class.create!(
      name: "Default Shelf Name",
      email: "default-shelf-name@example.com",
      password: "password123!",
      password_confirmation: "password123!"
    )

    expect(user.default_bookshelf.name).to eq("내 책장")
  end

  it "sets the default bookshelf visibility to public" do
    user = described_class.create!(
      name: "Default Shelf Visibility",
      email: "default-shelf-visibility@example.com",
      password: "password123!",
      password_confirmation: "password123!"
    )

    expect(user.default_bookshelf.visibility).to eq("public")
  end

  it "finds the default bookshelf by is_default instead of name" do
    user = described_class.create!(
      name: "Default Lookup User",
      email: "default-lookup-user@example.com",
      password: "password123!",
      password_confirmation: "password123!"
    )
    default_bookshelf = user.default_bookshelf

    default_bookshelf.update_column(:name, "Legacy Renamed Default")

    expect(user.default_bookshelf.reload).to eq(default_bookshelf)
  end

  it "destroys the user's bookshelves and entries without destroying books or other users' entries" do
    user = described_class.create!(
      name: "Destroy User",
      email: "destroy-user@example.com",
      password: "password123!",
      password_confirmation: "password123!"
    )
    other_user = described_class.create!(
      name: "Other Destroy User",
      email: "other-destroy-user@example.com",
      password: "password123!",
      password_confirmation: "password123!"
    )
    user_book = Book.create!(title: "User Book", authors_text: "Author")
    shared_book = Book.create!(title: "Shared Book", authors_text: "Author")
    user_bookshelf_id = user.default_bookshelf.id
    user_entry = user.bookshelf_entries.create!(book: user_book)
    other_entry = other_user.bookshelf_entries.create!(book: shared_book)

    expect { user.destroy! }
      .to change(described_class, :count).by(-1)
      .and change(BookshelfEntry, :count).by(-1)
      .and change(Bookshelf, :count).by(-1)
      .and change(Book, :count).by(0)

    expect(Bookshelf.exists?(user_bookshelf_id)).to be(false)
    expect(BookshelfEntry.exists?(user_entry.id)).to be(false)
    expect(Book.exists?(user_book.id)).to be(true)
    expect(BookshelfEntry.exists?(other_entry.id)).to be(true)
    expect(Book.exists?(shared_book.id)).to be(true)
  end
end
