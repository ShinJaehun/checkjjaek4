require "rails_helper"

RSpec.describe User, type: :model do
  it "normalizes a handle and keeps it after first assignment" do
    user = described_class.create!(name: "Handle", email: "handle-model@example.com", password: "password123!", handle: "Reader_42")

    expect(user.reload.handle).to eq("reader_42")
    expect(user.to_param).to eq("reader_42")
    expect(user.update(handle: "another_name")).to be(false)
    expect(user.reload.handle).to eq("reader_42")
  end

  it "keeps a numeric URL for a legacy account without a handle" do
    user = described_class.create!(name: "Legacy", email: "legacy-handle@example.com", password: "password123!")

    expect(user.handle).to be_nil
    expect(user.to_param).to eq(user.id.to_s)
  end

  it "rejects invalid, reserved, and duplicate handles" do
    described_class.create!(name: "First", email: "first-handle@example.com", password: "password123!", handle: "reader_one")
    user = described_class.new(name: "Second", email: "second-handle@example.com", password: "password123!")

    %w[12reader ab invalid-name admin READER_ONE].each do |handle|
      user.handle = handle
      expect(user).not_to be_valid
      expect(user.errors[:handle]).to be_present
    end
  end

  it "enforces case-insensitive handle uniqueness in the database" do
    described_class.create!(name: "First", email: "first-db-handle@example.com", password: "password123!", handle: "reader_one")
    second = described_class.create!(name: "Second", email: "second-db-handle@example.com", password: "password123!")

    expect {
      User.transaction(requires_new: true) { second.update_columns(handle: "READER_ONE") }
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "is not a global admin by default" do
    user = described_class.new

    expect(user).not_to be_global_admin
  end

  it "keeps suspension separate from withdrawal authentication state" do
    user = described_class.create!(
      name: "Suspended User",
      email: "suspended-user-model@example.com",
      password: "password123!",
      password_confirmation: "password123!",
      suspended_at: Time.current
    )

    expect(user).to be_suspended
    expect(user).not_to be_withdrawn
    expect(user.active_account?).to be(true)
    expect(user.active_for_authentication?).to be(true)

    user.update_columns(withdrawn_at: Time.current)
    expect(user.reload.inactive_message).to eq(:withdrawn)
  end

  it "assigns a default avatar index when the user is created" do
    user = described_class.create!(
      name: "Avatar User",
      email: "avatar-user@example.com",
      password: "password123!",
      password_confirmation: "password123!"
    )

    expect(user.default_avatar_index).to be_in(User::DEFAULT_AVATAR_INDEX_RANGE)
  end

  it "keeps an explicitly assigned default avatar index" do
    user = described_class.create!(
      name: "Explicit Avatar User",
      email: "explicit-avatar-user@example.com",
      password: "password123!",
      password_confirmation: "password123!",
      default_avatar_index: 12
    )

    expect(user.default_avatar_index).to eq(12)
  end

  it "is invalid with an out-of-range default avatar index" do
    user = described_class.new(
      name: "Invalid Avatar User",
      email: "invalid-avatar-user@example.com",
      password: "password123!",
      password_confirmation: "password123!",
      default_avatar_index: 33
    )

    expect(user).not_to be_valid
  end

  it "accepts a PNG avatar and rejects SVG without replacing the saved image" do
    user = User.create!(name: "Avatar reader", email: "avatar-model@example.com", password: "password123!")
    File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png")) do |file|
      user.avatar.attach(io: file, filename: "avatar.png", content_type: "image/png")
    end
    original_blob_id = user.avatar.blob.id

    user.avatar = { io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"></svg>'), filename: "avatar.svg", content_type: "image/svg+xml" }

    expect(user).not_to be_valid
    expect(user.errors[:avatar]).to be_present
    expect(User.find(user.id).avatar.blob.id).to eq(original_blob_id)
  end

  it "rejects an avatar larger than 5MB" do
    user = User.create!(name: "Large avatar reader", email: "large-avatar-model@example.com", password: "password123!")
    png_header = File.binread(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"))
    user.avatar = { io: StringIO.new(png_header + "x" * (User::MAX_AVATAR_SIZE + 1)), filename: "large.png", content_type: "image/png" }

    expect(user).not_to be_valid
    expect(user.errors[:avatar]).to be_present
    expect(User.find(user.id).avatar).not_to be_attached
  end

  it "chooses from the least used default avatar indexes" do
    described_class.create!(
      name: "Used Avatar One",
      email: "used-avatar-one@example.com",
      password: "password123!",
      password_confirmation: "password123!",
      default_avatar_index: 1
    )
    described_class.create!(
      name: "Used Avatar Two",
      email: "used-avatar-two@example.com",
      password: "password123!",
      password_confirmation: "password123!",
      default_avatar_index: 2
    )

    user = described_class.create!(
      name: "Least Used Avatar User",
      email: "least-used-avatar-user@example.com",
      password: "password123!",
      password_confirmation: "password123!"
    )

    expect(user.default_avatar_index).to be_between(3, 32).inclusive
  end

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
