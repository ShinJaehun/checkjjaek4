require "rails_helper"

RSpec.describe "BookSearches", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "book-search@example.com", password: "password123!", password_confirmation: "password123!") }

  it "redirects guests to sign in" do
    get book_search_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows search results to a signed-in user" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "미움받을 용기", page: 1).and_return(
      {
        results: [
          {
            title: "미움받을 용기",
            authors_text: "기시미 이치로, 고가 후미타케",
            publisher: "인플루엔셜",
            thumbnail: nil,
            isbn: "8996991341 9788996991342",
            contents_excerpt: "소개",
            url: "https://example.com"
          }
        ],
        meta: { total_count: 1, pageable_count: 1, is_end: true }
      }
    )

    get book_search_path, params: { query: "미움받을 용기" }

    expect(response.body).to include("미움받을 용기")
    expect(response.body).to include("기시미 이치로, 고가 후미타케")
    expect(response.body).to include("책 상세 보기")
    expect(response.body).to include("/books/lookup")
    expect(response.body).not_to include(">상세 보기<")
    expect(response.body).to include(I18n.t("book_search.pagination.page", page: 1))
    expect(response.body).not_to include(%(name="page"))
  end

  it "shows a bookshelf select when the user has multiple bookshelves" do
    user.bookshelves.create!(name: "읽을 책장", visibility: :private)
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "책장 선택", page: 1).and_return(
      {
        results: [
          {
            title: "책장 선택",
            authors_text: "저자",
            publisher: "출판사",
            thumbnail: nil,
            isbn: "9780000000099",
            contents_excerpt: "소개",
            url: "https://example.com/select-shelf"
          }
        ],
        meta: { total_count: 1, pageable_count: 1, is_end: true }
      }
    )

    get book_search_path, params: { query: "책장 선택" }

    expect(response.body).to include(I18n.t("bookshelf_entries.form.target_bookshelf"))
    expect(response.body).to include(%(name="bookshelf_entry[bookshelf_id]"))
    expect(response.body).to include("읽을 책장")
  end

  it "marks a search result already in the current user's shelf" do
    book = Book.create!(
      title: "이미 담긴 책",
      authors_text: "저자",
      isbn: "9780000000001",
      external_url: "https://example.com/already"
    )
    user.bookshelf_entries.create!(book:)
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "이미 담긴 책", page: 1).and_return(
      {
        results: [
          {
            title: "이미 담긴 책",
            authors_text: "저자",
            publisher: "출판사",
            thumbnail: nil,
            isbn: "9780000000001",
            contents_excerpt: "소개",
            url: "https://example.com/already"
          }
        ],
        meta: { total_count: 1, pageable_count: 1, is_end: true }
      }
    )

    expect {
      get book_search_path, params: { query: "이미 담긴 책" }
    }.not_to change { [ Book.count, BookshelfEntry.count ] }

    expect(response.body).to include(I18n.t("book_search.actions.in_shelf"))
    expect(response.body).not_to include(I18n.t("book_search.actions.add_to_shelf"))
    expect(response.body).to include(book_path(book))
    expect(response.body).not_to include("/books/lookup")
  end

  it "still shows add to shelf when the matching book is only in another user's shelf" do
    other_user = User.create!(name: "Other", email: "other-book-search@example.com", password: "password123!", password_confirmation: "password123!")
    book = Book.create!(
      title: "다른 사람 책",
      authors_text: "저자",
      isbn: "9780000000002",
      external_url: "https://example.com/other"
    )
    other_user.bookshelf_entries.create!(book:)
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "다른 사람 책", page: 1).and_return(
      {
        results: [
          {
            title: "다른 사람 책",
            authors_text: "저자",
            publisher: "출판사",
            thumbnail: nil,
            isbn: "9780000000002",
            contents_excerpt: "소개",
            url: "https://example.com/other"
          }
        ],
        meta: { total_count: 1, pageable_count: 1, is_end: true }
      }
    )

    get book_search_path, params: { query: "다른 사람 책" }

    expect(response.body).to include(I18n.t("book_search.actions.add_to_shelf"))
    expect(response.body).not_to include(I18n.t("book_search.actions.in_shelf"))
  end

  it "shows a next link when another search results page exists" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "책", page: 1).and_return(
      {
        results: [
          {
            title: "다음 페이지 책",
            authors_text: "저자",
            publisher: "출판사",
            thumbnail: nil,
            isbn: "123",
            contents_excerpt: "소개",
            url: "https://example.com"
          }
        ],
        meta: { total_count: 11, pageable_count: 11, is_end: false }
      }
    )

    get book_search_path, params: { query: "책" }

    expect(response.body).to include(I18n.t("book_search.pagination.next"))
    expect(response.body).to include("query=%EC%B1%85")
    expect(response.body).to include("page=2")
  end

  it "shows a previous link on later search results pages" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "책", page: 2).and_return(
      {
        results: [
          {
            title: "이전 페이지 책",
            authors_text: "저자",
            publisher: "출판사",
            thumbnail: nil,
            isbn: "123",
            contents_excerpt: "소개",
            url: "https://example.com"
          }
        ],
        meta: { total_count: 11, pageable_count: 11, is_end: true }
      }
    )

    get book_search_path, params: { query: "책", page: 2 }

    expect(response.body).to include(I18n.t("book_search.pagination.previous"))
    expect(response.body).to include("page=1")
    expect(response.body).not_to include(I18n.t("book_search.pagination.next"))
  end

  it "normalizes invalid page values to page 1" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "책", page: 1).and_return(
      {
        results: [
          {
            title: "보정된 페이지 책",
            authors_text: "저자",
            publisher: "출판사",
            thumbnail: nil,
            isbn: "123",
            contents_excerpt: "소개",
            url: "https://example.com"
          }
        ],
        meta: { total_count: 1, pageable_count: 1, is_end: true }
      }
    )

    get book_search_path, params: { query: "책", page: "wrong" }

    expect(response.body).to include(I18n.t("book_search.pagination.page", page: 1))
  end

  it "shows an empty state when no results are returned" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "없는책", page: 1).and_return(
      { results: [], meta: { total_count: 0, pageable_count: 0, is_end: true } }
    )

    get book_search_path, params: { query: "없는책" }

    expect(response.body).to include("검색 결과가 없습니다")
  end

  it "shows a safe error message when book search fails" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).with(query: "실패", page: 1).and_raise(BookSearches::KakaoAdapter::Error)

    get book_search_path, params: { query: "실패" }

    expect(response.body).to include("책 검색 중 오류가 발생했습니다.")
  end
end
