require "rails_helper"

RSpec.describe "User libraries", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader-library@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book_friend) { User.create!(name: "Friend", email: "friend-library@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "Preview Book", authors_text: "Preview Author") }
  let!(:bookshelf) { user.bookshelves.create!(name: "Preview Shelf", visibility: :private) }

  before do
    user.bookshelf_entries.create!(book:, bookshelf:)
  end

  it "renders an owner-only bookshelf entries preview" do
    sign_in user

    get user_library_path(user, bookshelf_id: bookshelf.id, preview: "bookshelf_entries")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Preview Shelf")
    expect(response.body).to include("Preview Book")
    expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))
  end

  it "rejects a non-owner bookshelf entries preview request" do
    BookFriendship.create!(requester: user, addressee: book_friend, status: :accepted)
    sign_in book_friend

    get user_library_path(user, bookshelf_id: bookshelf.id, preview: "bookshelf_entries")

    expect(response).to have_http_status(:forbidden)
  end
end
