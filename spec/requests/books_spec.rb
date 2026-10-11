require "rails_helper"

RSpec.describe "Books", type: :request do
  include ActiveSupport::Testing::TimeHelpers

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

    it "shows the current bookshelf context for a shelved book" do
      bookshelf = user.bookshelves.create!(name: "상세 책장", visibility: :private)
      user.bookshelf_entries.create!(book:, bookshelf:, status: :reading)
      sign_in user

      get book_path(book)

      expect(response.body).to include(I18n.t("books.show.current_bookshelf"))
      expect(response.body).to include("상세 책장")
    end

    it "shows a bookshelf move form when the user has multiple bookshelves" do
      bookshelf = user.bookshelves.create!(name: "현재 상세 책장", visibility: :private)
      target_bookshelf = user.bookshelves.create!(name: "옮길 상세 책장", visibility: :private)
      entry = user.bookshelf_entries.create!(book:, bookshelf:)
      sign_in user

      get book_path(book)

      expect(response.body).to include(%(action="#{move_bookshelf_entry_path(entry)}"))
      expect(response.body).to include(%(name="bookshelf_id"))
      expect(response.body).to include(%(value="book"))
      expect(response.body).to include(target_bookshelf.name)
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

    it "redirects guests before showing the library context" do
      user.bookshelf_entries.create!(book:, status: :reading)

      get book_path(book)

      expect(response).to redirect_to(new_user_session_path)
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
    it "previews a new search result without writing and adds it to the shelf on POST" do
      sign_in user
      result = {
        title: "검색한 책", authors_text: "검색 저자", publisher: "검색 출판사",
        thumbnail: "https://example.com/cover.jpg", isbn: "9780000000001",
        contents_excerpt: "검색 설명", url: "https://example.com/books/1"
      }
      token = search_result_token_for(result)

      expect {
        get lookup_books_path, params: { search_result_token: token }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("검색한 책", "검색 저자", "검색 설명", "https://example.com/cover.jpg")
      expect(response.body).to include('name="search_result_token"', I18n.t("bookshelf_entries.new.title"))
      expect(response.body).not_to include('name="book_id"')

      expect {
        post bookshelf_entries_path, params: { search_result_token: token }
      }.to change(Book, :count).by(1).and change(BookshelfEntry, :count).by(1)

      expect(response).to redirect_to(book_path(Book.find_by!(isbn: "9780000000001")))
    end

    it "redirects to an existing book without changing its metadata" do
      existing_book = Book.create!(
        title: "기존 책",
        authors_text: "기존 저자",
        isbn: "9780000000002",
        external_url: "https://example.com/books/2"
      )
      sign_in user
      token = search_result_token_for({
        title: "기존 책 새 제목", authors_text: "검색 저자", publisher: "검색 출판사",
        thumbnail: nil, isbn: "9780000000002", contents_excerpt: "검색 설명",
        url: "https://example.com/books/2"
      })
      original_attributes = existing_book.attributes

      expect {
        get lookup_books_path, params: { search_result_token: token }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }

      expect(response).to redirect_to(book_path(existing_book))
      expect(existing_book.reload.attributes).to eq(original_attributes)
    end

    it "does not write when search ISBN and URL identify different books" do
      Book.create!(title: "ISBN 책", isbn: "9780000000002")
      Book.create!(title: "URL 책", external_url: "https://example.com/collision")
      sign_in user
      token = search_result_token_for({
        title: "충돌 책", authors_text: "저자", publisher: "", thumbnail: nil,
        isbn: "9780000000002", contents_excerpt: "", url: "https://example.com/collision"
      })

      expect {
        get lookup_books_path, params: { search_result_token: token }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }

      expect(response).to redirect_to(book_search_path)
      expect(flash[:alert]).to eq(I18n.t("book_search.errors.identity_conflict"))
    end

    it "previews a book with unsafe URLs using the default cover without writing" do
      sign_in user
      token = BookSearches::ResultToken.issue({
        title: "표지 없는 책", authors_text: "저자", publisher: "", thumbnail: "javascript:alert(1)",
        isbn: "9780000000002", contents_excerpt: "소개", url: "file:///etc/passwd"
      }, user: user)

      expect {
        get lookup_books_path, params: { search_result_token: token }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("표지 없는 책", "저자", "소개", I18n.t("books.thumbnail.no_thumbnail"))
      expect(response.body).not_to include("javascript:alert(1)", "file:///etc/passwd")
    end

    it "rejects a tampered or expired search result without writing" do
      sign_in user
      token = search_result_token_for({
        title: "만료 책", authors_text: "저자", publisher: "출판사", thumbnail: nil,
        isbn: "9780000000003", contents_excerpt: "소개", url: "https://example.com/books/3"
      })

      expect {
        get lookup_books_path, params: { search_result_token: "#{token}tampered" }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }
      expect(response).to redirect_to(book_search_path)
      expect(flash[:alert]).to eq(I18n.t("book_search.errors.invalid_result"))

      travel_to(31.minutes.from_now) do
        expect {
          get lookup_books_path, params: { search_result_token: token }
        }.not_to change { [ Book.count, BookshelfEntry.count ] }
        expect(response).to redirect_to(book_search_path)
        expect(flash[:alert]).to eq(I18n.t("book_search.errors.invalid_result"))
      end
    end

    it "keeps the group context through search preview and shelf creation" do
      group_admin = User.create!(name: "Admin", email: "book-lookup-group-admin@example.com", password: "password123!")
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :private_group)
      group.group_memberships.create!(user:, status: :active)
      sign_in user
      token = search_result_token_for(
        {
          title: "동아리 검색 책", authors_text: "저자", publisher: "출판사", thumbnail: nil,
          isbn: "9780000000004", contents_excerpt: "소개", url: "https://example.com/books/4"
        }, group_id: group.id
      )

      get lookup_books_path, params: { search_result_token: token, group_id: group.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="group_id"', "동아리 검색 책")

      post bookshelf_entries_path, params: { search_result_token: token, group_id: group.id }

      expect(response).to redirect_to(book_path(Book.find_by!(isbn: "9780000000004"), group_id: group.id))
    end
  end

  def search_result_token_for(result, group_id: nil)
    allow(BookSearches::SearchService).to receive(:call).with(query: result[:title], page: 1).and_return(
      results: [ result ], meta: { total_count: 1, pageable_count: 1, is_end: true }
    )
    get book_search_path, params: { query: result[:title], group_id: }

    Nokogiri::HTML(response.body).at_css('input[name="search_result_token"]')["value"]
  end
end
