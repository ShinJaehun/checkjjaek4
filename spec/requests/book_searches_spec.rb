require "rails_helper"

RSpec.describe "BookSearches", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "book-search@example.com", password: "password123!", password_confirmation: "password123!") }

  it "redirects guests to sign in" do
    get book_search_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows search results to a signed-in user" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).and_return(
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
  end

  it "shows an empty state when no results are returned" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).and_return(
      { results: [], meta: { total_count: 0, pageable_count: 0, is_end: true } }
    )

    get book_search_path, params: { query: "없는책" }

    expect(response.body).to include("검색 결과가 없습니다")
  end

  it "shows a safe error message when book search fails" do
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)

    get book_search_path, params: { query: "실패" }

    expect(response.body).to include("책 검색 중 오류가 발생했습니다.")
  end
end
