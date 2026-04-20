require "rails_helper"

RSpec.describe "Books", type: :request do
  let!(:user) { User.create!(name: "Shelf Owner", email: "shelf-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "서재에 있는 책", authors_text: "저자") }

  describe "GET /books/:id" do
    it "allows the shelf owner to open the book page" do
      user.bookshelf_entries.create!(book:, status: :reading)
      sign_in user

      get book_path(book)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("서재에 있는 책")
    end
  end
end
