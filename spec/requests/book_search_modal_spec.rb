require "rails_helper"

RSpec.describe "Shared book search", type: :request do
  let(:user) { User.create!(name: "Search reader", email: "modal-reader@example.com", password: "password123!") }
  let(:group) { Group.create!(name: "Search club", group_admin: user, group_type: :private_group, lifecycle_status: :active) }

  before { sign_in user }

  it "renders a standalone frame with group context and searches without creating books" do
    book = Book.create!(title: "Local book")
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)

    expect {
      get book_search_path, params: { modal: "1", query: "Local", group_id: group.id }
    }.not_to change { [ Book.count, BookshelfEntry.count ] }

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('turbo-frame#book_search_modal_results')).to be_present
    expect(page.at_css('input[name="group_id"]')["value"]).to eq(group.id.to_s)
    expect(page.at_css('input[name="modal"]')["value"]).to eq("1")
    book_link = page.css("a[data-turbo-frame='_top']").find do |link|
      URI.parse(link["href"]).path == book_path(book)
    end
    expect(book_link).to be_present
    link_params = Rack::Utils.parse_query(URI.parse(book_link["href"]).query)
    expect(link_params["group_id"]).to eq(group.id.to_s)
    return_uri = URI.parse(link_params.fetch("return_to"))
    expect(return_uri.path).to eq(book_search_path)
    expect(Rack::Utils.parse_query(return_uri.query)).to include(
      "group_id" => group.id.to_s, "page" => "1", "query" => "Local"
    )
    expect(page.text).to include(I18n.t("search_ui.external_unavailable"), group.name, I18n.t("books.thumbnail.no_thumbnail"))
    expect(response.body).not_to include("<!DOCTYPE html>")
  end

  it "searches existing authors and publishers and escapes SQL wildcard characters" do
    author_match = Book.create!(title: "One", authors_text: "Literal%Author")
    publisher_match = Book.create!(title: "Two", publisher: "Literal%Press")
    excluded = Book.create!(title: "Wrong", authors_text: "Literal unrelated")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })

    get book_search_path, params: { query: "Literal%", modal: "1" }

    expect(response.body).to include(author_match.title, publisher_match.title)
    expect(response.body).not_to include(excluded.title)
  end

  it "keeps distinct cards and existing-book links for DB books with identical titles" do
    books = 2.times.map { Book.create!(title: "Same local title") }
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    get book_search_path, params: { query: "Same local", modal: "1" }
    cards = Nokogiri::HTML(response.body).css("article")
    expect(cards.map { |card| card["id"] }.uniq.size).to eq(2)
    links = cards.map { |card| URI.parse(card.at_css("a")["href"]) }
    expect(links.map(&:path)).to eq(books.map { |book| book_path(book) })
    links.each do |link|
      return_to = Rack::Utils.parse_query(link.query).fetch("return_to")
      return_uri = URI.parse(return_to)
      expect(return_uri.path).to eq(book_search_path)
      expect(Rack::Utils.parse_query(return_uri.query)).to include(
        "page" => "1", "query" => "Same local"
      )
    end
  end

  it "uses signed previews for partial external results without inventing a book id" do
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "Partial book", url: "https://example.com/partial" } ], meta: { pageable_count: 1, is_end: true }
    )
    expect {
      get book_search_path, params: { query: "Partial", modal: "1", group_id: group.id }
    }.not_to change(Book, :count)
    page = Nokogiri::HTML(response.body)
    link = page.at_css('a[href^="/books/lookup"]')
    expect(link).to be_present
    expect(page.at_css('input[name="book_id"]')).to be_nil
    token = page.at_css('input[name="search_result_token"]')["value"]
    expect(BookSearches::ResultToken.verify(token, user: user)[:title]).to eq("Partial book")
    expect { get link["href"] }.not_to change(Book, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("bookshelf_entries.new.title"))
    expect {
      post bookshelf_entries_path, params: { search_result_token: token, group_id: group.id }
    }.to change(Book, :count).by(1)
    expect(response).to redirect_to(book_path(Book.last, group_id: group.id))
    expect {
      post bookshelf_entries_path, params: { search_result_token: token, group_id: group.id }
    }.not_to change { [ Book.count, BookshelfEntry.count ] }
  end

  it "reuses existing DB books and keeps group context on registration" do
    book = Book.create!(title: "Stored book", description: "Original metadata")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    get book_search_path, params: { query: "Stored", modal: "1", group_id: group.id }
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('input[name="book_id"]')["value"]).to eq(book.id.to_s)
    expect {
      post bookshelf_entries_path, params: { book_id: book.id, group_id: group.id }
    }.not_to change(Book, :count)
    expect(response).to redirect_to(book_path(book, group_id: group.id))
    expect(book.reload.description).to eq("Original metadata")
  end

  it "keeps pagination and group context when DB results continue and the external service fails" do
    11.times { |index| Book.create!(title: "Paged local #{index}") }
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)
    get book_search_path, params: { query: "Paged", modal: "1", group_id: group.id }
    page = Nokogiri::HTML(response.body)
    expect(page.css("article").size).to eq(10)
    next_link = page.css("a").find { |link| link.text == I18n.t("book_search.pagination.next") }
    expect(next_link).to be_present
    get next_link["href"]
    expect(Nokogiri::HTML(response.body).css("article").size).to eq(1)
    expect(response.body).to include('name="group_id"')
  end

  it "enforces the same group authorization for modal and full-page search" do
    outsider = User.create!(name: "Outsider", email: "modal-outsider@example.com", password: "password123!")
    group
    sign_in outsider
    [nil, "1"].each do |modal|
      get book_search_path, params: { group_id: group.id, modal: modal }
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include(group.name)
    end
  end
end
