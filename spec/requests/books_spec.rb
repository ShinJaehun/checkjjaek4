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
      expect(response.body).to include("상태 저장")
      expect(response.body).to include("짹")
    end

    it "shows the book as read-only when the user has no bookshelf entry" do
      other_user = User.create!(name: "Other Reader", email: "other-book-reader@example.com", password: "password123!", password_confirmation: "password123!")
      book.jjaeks.create!(user: other_user, content: "다른 독자의 공개 Jjaek")
      sign_in user

      get book_path(book)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("서재에 있는 책")
      expect(response.body).to include("다른 독자의 공개 Jjaek")
      expect(response.body).not_to include("상태 저장")
      expect(response.body).not_to include('name="jjaek[content]"')
    end
  end

  describe "GET /books/lookup" do
    it "creates a book without creating a bookshelf entry and redirects to the book page" do
      sign_in user

      expect {
        get lookup_books_path, params: {
          title: "검색한 책",
          authors_text: "검색 저자",
          publisher: "검색 출판사",
          isbn: "9780000000001",
          description: "검색 설명",
          external_url: "https://example.com/books/1"
        }
      }.to change(Book, :count).by(1)
        .and change(BookshelfEntry, :count).by(0)

      created_book = Book.find_by!(isbn: "9780000000001")
      expect(response).to redirect_to(book_path(created_book))
    end

    it "reuses an existing book without creating a bookshelf entry and redirects to the book page" do
      existing_book = Book.create!(
        title: "기존 책",
        authors_text: "기존 저자",
        isbn: "9780000000002",
        external_url: "https://example.com/books/2"
      )
      sign_in user

      expect {
        get lookup_books_path, params: {
          title: "기존 책 새 제목",
          authors_text: "검색 저자",
          publisher: "검색 출판사",
          isbn: "9780000000002",
          description: "검색 설명",
          external_url: "https://example.com/books/2"
        }
      }.to change(Book, :count).by(0)
        .and change(BookshelfEntry, :count).by(0)

      expect(response).to redirect_to(book_path(existing_book))
    end
  end
end
