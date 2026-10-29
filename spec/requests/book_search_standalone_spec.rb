require "rails_helper"

RSpec.describe "Standalone book search", type: :request do
  let(:user) { User.create!(name: "Search reader", email: "standalone-reader@example.com", password: "password123!") }
  let(:group) { Group.create!(name: "Search club", group_admin: user, group_type: :private_group, lifecycle_status: :active) }

  before { sign_in user }

  it "offers one global input-only search dialog with a validated origin and no posting group" do
    shelf = user.bookshelves.create!(name: "Search source", visibility: :private)
    origins = [ root_path, user_library_path(user, bookshelf_id: shelf.id, sort: "title"), group_path(group),
                book_search_path(group_id: group.id, search_origin: group_path(group)) ]

    origins.each do |origin|
      get origin
      page = Nokogiri::HTML(response.body)
      expect(page.css("#global-book-search-dialog").size).to eq(1)
      expect(page.at_css("header button[aria-controls='global-book-search-dialog']").text).to eq(I18n.t("book_search.nav"))
      dialog = page.at_css("#global-book-search-dialog")
      expect(dialog["open"]).to be_nil
      form = dialog.at_css("form")
      expect(form["action"]).to eq(book_search_path)
      expect(form["method"]).to eq("get")
      expect(form.at_css("input[name='query']")["autofocus"]).to be_present
      expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("book_search.form.submit"))
      expect(form.css("input[name='group_id'], input[name='page']")).to be_empty
      expected_origin = origin == origins.last ? group_path(group) : origin
      expect(form.at_css("input[name='search_origin']")["value"]).to eq(expected_origin)
      expect(dialog.css("article, turbo-frame")).to be_empty
      expect(dialog.text).not_to include(I18n.t("book_search.modal.group_destination", group_name: group.name))
      expect(page.css("#global-book-search-query").size).to eq(1)
    end
  end

  it "opens the shared search dialog from the library while keeping its validated origin" do
    shelf = user.bookshelves.create!(name: "Search source", visibility: :private)
    origin = user_library_path(user, bookshelf_id: shelf.id, sort: "title")
    get origin
    page = Nokogiri::HTML(response.body)
    button = page.at_css("main button[aria-controls='global-book-search-dialog']")
    expect(button.text).to eq(I18n.t("book_search.nav"))
    expect(button["data-action"]).to eq("book-modal#open")
    expect(page.at_css("body")["data-controller"]).to eq("book-modal")
    expect(page.at_css("header")["data-controller"]).to eq("mobile-navigation")
    expect(page.css("#global-book-search-dialog").size).to eq(1)
    expect(page.css("main a[href^='#{book_search_path}']")).to be_empty
    form = page.at_css("#global-book-search-dialog form")
    expect(form["action"]).to eq(book_search_path)
    expect(form["method"]).to eq("get")
    expect(form.at_css("input[name='search_origin']")["value"]).to eq(origin)
    expect(form.at_css("input[name='group_id']")).to be_nil

    get form["action"], params: { query: "", search_origin: origin }
    expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(origin)
  end

  it "offers a separate club search dialog with its posting destination and validated origin" do
    get group_path(group)
    page = Nokogiri::HTML(response.body)
    expect(page.css("#group-book-search-dialog").size).to eq(1)
    dialog = page.at_css("#group-book-search-dialog")
    expect(dialog["open"]).to be_nil
    expect(dialog.at_css("h2").text).to eq(I18n.t("book_search.title"))
    expect(dialog.text).to include(I18n.t("book_search.modal.group_destination", group_name: group.name))
    form = dialog.at_css("form")
    expect(form["action"]).to eq(book_search_path)
    expect(form["method"]).to eq("get")
    expect(form.at_css("input[name='query']")["id"]).to eq("group-book-search-query")
    expect(form.at_css("input[name='query']")["autofocus"]).to be_present
    expect(form.at_css("input[name='group_id']")["value"]).to eq(group.id.to_s)
    expect(form.at_css("input[name='search_origin']")["value"]).to eq(group_path(group))
    expect(page.at_css("#global-book-search-dialog input[name='group_id']")).to be_nil
    expect(page.at_css("#global-book-search-dialog").text).not_to include(
      I18n.t("book_search.modal.group_destination", group_name: group.name)
    )

    get form["action"], params: { group_id: group.id, search_origin: group_path(group) }
    expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(group_path(group))
  end

  it "uses the club origin only for returning when a global search selects a shelved book" do
    book = Book.create!(title: "Global club search book")
    user.bookshelf_entries.create!(book: book)
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    get book_search_path, params: { query: "Global club", search_origin: group_path(group) }

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("main input[name='group_id']")).to be_nil
    expect(page.at_css("a[data-back-link]")["href"]).to eq(group_path(group))
    link = page.at_css("main article a")
    results_path = book_search_path(query: "Global club", page: 1, search_origin: group_path(group))
    expect(link["href"]).to eq(book_path(book, return_to: results_path))
    get link["href"]
    form = Nokogiri::HTML(response.body).at_css("#book-jjaek-form form")
    expect(form["action"]).to eq(jjaeks_path)
    expect(form.at_css("input[name='book_post_destination'][checked]")["value"]).to eq("personal")
    expect(form.at_css("select[name='jjaek[group_id]']")["disabled"]).to be_present
  end

  it "shows the search form without requesting results when the query is absent" do
    expect(BookSearches::SearchService).not_to receive(:call)
    get book_search_path, params: { group_id: group.id, search_origin: group_path(group) }

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    form = page.at_css("main form")
    expect(form["action"]).to eq(book_search_path)
    expect(form["method"]).to eq("get")
    expect(form.at_css("input[name='query']")).to be_present
    expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("book_search.form.submit"))
    expect(form.at_css("input[name='group_id']")["value"]).to eq(group.id.to_s)
    expect(form.at_css("input[name='search_origin']")["value"]).to eq(group_path(group))
    expect(form.ancestors("noscript, dialog, turbo-frame")).to be_empty
    expect(page.css("main article")).to be_empty
    expect(page.text).not_to include(I18n.t("book_search.empty.title"))
  end

  it "keeps input and results together and restarts a changed query on page one" do
    Book.create!(title: "Replacement search result")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    get book_search_path, params: { query: "Previous", page: 2, group_id: group.id, search_origin: group_path(group) }

    form = Nokogiri::HTML(response.body).at_css("main form")
    expect(form.at_css("input[name='query']")["value"]).to eq("Previous")
    expect(form.at_css("input[name='group_id']")["value"]).to eq(group.id.to_s)
    expect(form.at_css("input[name='search_origin']")["value"]).to eq(group_path(group))
    expect(form.css("input[name='page'], input[name='modal'], input[name='return_to']")).to be_empty
    get form["action"], params: { query: "Replacement", group_id: group.id, search_origin: group_path(group) }
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("main input[name='query']")["value"]).to eq("Replacement")
    expect(page.at_css("main article").text).to include("Replacement search result")
    expect(page.text).to include(I18n.t("book_search.pagination.page", page: 1))
    expect(page.at_css("a[data-back-link]")["href"]).to eq(group_path(group))
    expect(response.body).to include("<!DOCTYPE html>")
  end

  it "falls back to the club or own library without a valid origin" do
    other = User.create!(name: "Other", email: "search-other@example.com", password: "password123!")
    private_group = Group.create!(name: "Inaccessible", group_admin: other, group_type: :private_group, lifecycle_status: :active)
    [ nil, "https://example.com", "//example.com", "/users/sign_out", group_path(private_group), [ root_path ] ].each do |origin|
      get book_search_path, params: { search_origin: origin }
      expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(user_library_path(user))

      get book_search_path, params: { group_id: group.id, search_origin: origin }
      expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(group_path(group))
    end
  end

  it "keeps the search result return path after a Turbo card replacement" do
    book = Book.create!(title: "Turbo search book")
    search_path = book_search_path(query: "Turbo", page: 2, group_id: group.id, search_origin: group_path(group))

    post bookshelf_entries_path, params: {
      book_id: book.id, group_id: group.id, bookshelf_entry_source: "book_search", return_to: search_path
    }, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    page = Nokogiri::HTML(response.body)
    stream = page.at_css('turbo-stream[action="replace"]')
    expect(stream["target"]).to eq("book_search_result_stored_#{book.id}")
    link = stream.at_css("template article a")
    expect(link["href"]).to eq(book_path(book, group_id: group.id, return_to: search_path))
    expect(stream.text).to include(I18n.t("book_search.actions.in_shelf"))
    get link["href"]
    expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(search_path)
  end

  it "renders a full search page with group context without creating books" do
    book = Book.create!(title: "Local book")
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)

    expect {
      get book_search_path, params: { query: "Local", group_id: group.id }
    }.not_to change { [ Book.count, BookshelfEntry.count ] }

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('input[name="group_id"]')["value"]).to eq(group.id.to_s)
    book_link = page.css("a").find do |link|
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
    expect(response.body).to include("<!DOCTYPE html>")
  end

  it "searches existing authors and publishers and escapes SQL wildcard characters" do
    author_match = Book.create!(title: "One", authors_text: "Literal%Author")
    publisher_match = Book.create!(title: "Two", publisher: "Literal%Press")
    excluded = Book.create!(title: "Wrong", authors_text: "Literal unrelated")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })

    get book_search_path, params: { query: "Literal%" }

    expect(response.body).to include(author_match.title, publisher_match.title)
    expect(response.body).not_to include(excluded.title)
  end

  it "keeps distinct cards and existing-book links for DB books with identical titles" do
    books = 2.times.map { Book.create!(title: "Same local title") }
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    get book_search_path, params: { query: "Same local" }
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
      get book_search_path, params: { query: "Partial", page: 2, group_id: group.id, search_origin: group_path(group) }
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
    preview = Nokogiri::HTML(response.body)
    search_path = book_search_path(query: "Partial", page: 2, group_id: group.id, search_origin: group_path(group))
    expect(preview.at_css("a[data-back-link]")["href"]).to eq(search_path)
    return_to = preview.at_css('input[name="return_to"]')["value"]
    expect(return_to).to eq(search_path)
    expect {
      post bookshelf_entries_path, params: { search_result_token: token, group_id: group.id, return_to: return_to }
    }.to change(Book, :count).by(1).and change(BookshelfEntry, :count).by(1)
    expect(response).to redirect_to(book_path(Book.last, group_id: group.id, return_to: search_path))
    follow_redirect!
    expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(search_path)
    expect {
      post bookshelf_entries_path, params: { search_result_token: token, group_id: group.id, return_to: return_to }
    }.not_to change { [ Book.count, BookshelfEntry.count ] }
  end

  it "reuses existing DB books and keeps group context on registration" do
    book = Book.create!(title: "Stored book", description: "Original metadata")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    get book_search_path, params: { query: "Stored", group_id: group.id, search_origin: group_path(group) }
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('input[name="book_id"]')["value"]).to eq(book.id.to_s)
    search_path = page.at_css('input[name="return_to"]')["value"]
    expect(search_path).to eq(book_search_path(query: "Stored", page: 1, group_id: group.id, search_origin: group_path(group)))
    expect {
      post bookshelf_entries_path, params: { book_id: book.id, group_id: group.id, return_to: search_path }
    }.not_to change(Book, :count)
    expect(response).to redirect_to(book_path(book, group_id: group.id, return_to: search_path))
    expect(book.reload.description).to eq("Original metadata")
  end

  it "keeps pagination and group context when DB results continue and the external service fails" do
    11.times { |index| Book.create!(title: "Paged local #{index}") }
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)
    get book_search_path, params: { query: "Paged", group_id: group.id, search_origin: group_path(group) }
    page = Nokogiri::HTML(response.body)
    expect(page.css("article").size).to eq(10)
    next_link = page.css("a").find { |link| link.text == I18n.t("book_search.pagination.next") }
    expect(next_link).to be_present
    expect(Rack::Utils.parse_query(URI.parse(next_link["href"]).query)).to include(
      "query" => "Paged", "page" => "2", "group_id" => group.id.to_s, "search_origin" => group_path(group)
    )
    get next_link["href"]
    page = Nokogiri::HTML(response.body)
    expect(page.css("article").size).to eq(1)
    expect(response.body).to include('name="group_id"')
    expect(page.at_css('main input[name="query"]')["value"]).to eq("Paged")
    expect(page.at_css('main input[name="search_origin"]')["value"]).to eq(group_path(group))
    expect(page.at_css("a[data-back-link]")["href"]).to eq(group_path(group))
    search_path = book_search_path(query: "Paged", page: 2, group_id: group.id, search_origin: group_path(group))
    get page.at_css("article a")["href"]
    expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(search_path)
    get search_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[data-back-link]")["href"]).to eq(group_path(group))
    previous_link = page.css("a").find { |link| link.text == I18n.t("book_search.pagination.previous") }
    get previous_link["href"]
    expect(Nokogiri::HTML(response.body).css("article").size).to eq(10)
  end

  it "rejects search in an inaccessible group" do
    outsider = User.create!(name: "Outsider", email: "standalone-outsider@example.com", password: "password123!")
    group
    sign_in outsider
    get book_search_path, params: { group_id: group.id }
    expect(response).not_to have_http_status(:ok)
    expect(response.body).not_to include(group.name)
  end
end
