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
      expect(response.body).to include(I18n.t("books.show.save_state"))
      expect(response.body).to include('name="jjaek[content]"')
      expect(response.body).to include(I18n.t("jjaeks.actions.publish_book"))
    end

    it "shows the book-context label for book-linked jjaeks" do
      user.bookshelf_entries.create!(book:, status: :reading)
      book_jjaek = user.jjaeks.create!(book:, content: "BOOK_CONTEXT_LABEL_BODY")
      sign_in user

      get book_path(book)

      expect(response.body).to include(book_jjaek.content)
      expect(response.body).to include(%(id="comments_panel_book_#{book.id}_jjaek_#{book_jjaek.id}"))
      expect(response.body).to include(%(href="/jjaeks/#{book_jjaek.id}/comments?book_id=#{book.id}&amp;comments_context=book))
      expect(response.body).to include(%(data-turbo-stream="true"))
      expect(response.body).to include(%(href="/jjaeks/#{book_jjaek.id}#comments_panel_jjaek_#{book_jjaek.id}"))
      expect(response.body).to include(user.name)
      expect(response.body).to include(user_path(user))
      expect(response.body).to include(book.title)
      expect(response.body).to include(book_path(book))
      expect(response.body).to include("님의 책짹")
    end

    it "shows only original book jjaeks on the book page while keeping the requote count on the original" do
      user.bookshelf_entries.create!(book:, status: :reading)
      original = user.jjaeks.create!(book:, content: "BOOK_ORIGINAL_BODY")
      requote = user.jjaeks.create!(book:, content: "BOOK_REQUOTE_BODY", quoted_jjaek: original)
      sign_in user

      get book_path(book)

      expect(response.body).to include(original.content)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1))
      expect(response.body).not_to include(requote.content)
    end

    it "shows the book as read-only when the user has no bookshelf entry" do
      other_user = User.create!(name: "Other Reader", email: "other-book-reader@example.com", password: "password123!", password_confirmation: "password123!")
      book.jjaeks.create!(user: other_user, content: "다른 독자의 공개 Jjaek")
      sign_in user

      get book_path(book)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("서재에 있는 책")
      expect(response.body).to include("다른 독자의 공개 Jjaek")
      expect(response.body).to include(I18n.t("books.show.read_only_description"))
      expect(response.body).to include(%(action="#{bookshelf_entries_path}"))
      expect(response.body).to include(%(name="book_id"))
      expect(response.body).to include(%(value="#{book.id}"))
      expect(response.body).not_to include("/bookshelf_entries/new")
      expect(response.body).to include(I18n.t("bookshelf_entries.new.title"))
      expect(response.body).not_to include('name="bookshelf_entry[status]"')
      expect(response.body).not_to include('name="jjaek[content]"')
    end

    it "shows a bookshelf select in the read-only add form when the user has multiple bookshelves" do
      user.bookshelves.create!(name: "따로 담을 책장", visibility: :private)
      sign_in user

      get book_path(book)

      expect(response.body).to include(I18n.t("bookshelf_entries.form.target_bookshelf"))
      expect(response.body).to include(%(name="bookshelf_entry[bookshelf_id]"))
      expect(response.body).to include("따로 담을 책장")
    end

    it "adds a read-only book to the shelf and returns to the writable book page" do
      sign_in user

      expect {
        post bookshelf_entries_path, params: {
          book_id: book.id
        }
      }.to change(user.bookshelf_entries, :count).by(1)

      expect(response).to redirect_to(book_path(book))
      expect(user.bookshelf_entries.find_by!(book:).status).to be_nil

      follow_redirect!

      expect(response.body).to include(I18n.t("books.show.save_state"))
      expect(response.body).to include('name="jjaek[content]"')

      document = Nokogiri::HTML(response.body)
      status_select = document.at_css('select[name="bookshelf_entry[status]"]')
      status_radios = document.css('input[type="radio"][name="bookshelf_entry[status]"]')

      expect(status_select).to be_nil
      expect(status_radios.map { |radio| radio["value"] }).to match_array(BookshelfEntry.statuses.keys)
      expect(status_radios.any? { |radio| radio["checked"].present? }).to be(false)
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
