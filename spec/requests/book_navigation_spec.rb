require "rails_helper"

RSpec.describe "Book navigation", type: :request do
  let(:reader) { User.create!(name: "Reader", email: "book-navigation@example.com", password: "password123!") }
  let(:other) { User.create!(name: "Other", email: "book-navigation-other@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Navigation book", authors_text: "Author", isbn: "9780000000002") }

  def back_link
    Nokogiri::HTML(response.body).at_css("a[data-back-link]")
  end

  it "returns book links to the selected library shelf and sort order" do
    entry = reader.bookshelf_entries.create!(book: book)
    origin = user_library_path(reader, bookshelf_id: entry.bookshelf_id, sort: "title")
    sign_in reader
    get origin
    page = Nokogiri::HTML(response.body)
    link = page.at_css("a[href^='/books/#{book.id}?']")
    expect(Rack::Utils.parse_query(URI.parse(link["href"]).query)["return_to"]).to eq(origin)
    get link["href"]
    expect(back_link["href"]).to eq(origin)
  end

  it "separates the library origin from search result returns through forms and pagination" do
    entry = reader.bookshelf_entries.create!(book: book)
    origin = user_library_path(reader, bookshelf_id: entry.bookshelf_id, sort: "recent")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: false })
    sign_in reader
    get book_search_path, params: { query: "Navigation", page: "1", search_origin: origin }
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='search_origin']")["value"]).to eq(origin)
    expect(back_link["href"]).to eq(origin)
    pagination = page.css("nav a").find { |link| link.text == I18n.t("book_search.pagination.next") }
    expect(Rack::Utils.parse_query(URI.parse(pagination["href"]).query)).to include(
      "query" => "Navigation", "page" => "2", "search_origin" => origin
    )
    detail = page.at_css("a[href^='/books/#{book.id}?']")
    results_path = book_search_path(query: "Navigation", page: "1", search_origin: origin)
    expect(Rack::Utils.parse_query(URI.parse(detail["href"]).query)["return_to"]).to eq(results_path)
    get detail["href"]
    expect(back_link["href"]).to eq(results_path)
    get back_link["href"]
    expect(back_link["href"]).to eq(origin)
  end

  it "returns standalone search results to their query and page" do
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: book.title, authors_text: "Author", isbn: book.isbn } ], meta: { is_end: true }
    )
    sign_in reader
    get book_search_path, params: { query: "Navigation", page: "2" }
    link = Nokogiri::HTML(response.body).at_css("article a")
    expect(link).to be_present
    origin = book_search_path(query: "Navigation", page: "2")
    expect(Rack::Utils.parse_query(URI.parse(link["href"]).query)["return_to"]).to eq(origin)
    get link["href"]
    if response.redirect?
      expect(response).to redirect_to(book_path(book, return_to: origin))
      follow_redirect!
    end
    expect(response).to have_http_status(:ok)
    expect(back_link["href"]).to eq(origin)
  end

  it "preserves the search origin when lookup resolves an existing book and when shelving it" do
    origin = book_search_path(query: "Navigation", page: "2")
    sign_in reader
    token = BookSearches::ResultToken.issue({ title: book.title, authors_text: "Author", isbn: book.isbn }, user: reader)
    get lookup_books_path, params: { search_result_token: token, return_to: origin }
    expect(response).to redirect_to(book_path(book, return_to: origin))
    follow_redirect!
    expect(back_link["href"]).to eq(origin)
    form = Nokogiri::HTML(response.body).at_css("form[action='#{bookshelf_entries_path}']")
    expect(form.at_css("input[name='return_to']")["value"]).to eq(origin)
    post bookshelf_entries_path, params: { book_id: book.id, return_to: origin }
    expect(response).to redirect_to(book_path(book, return_to: origin))
  end

  it "uses the group origin while retaining the existing book writing context" do
    group = Group.create!(name: "Readers", group_admin: reader, group_type: :private_group, lifecycle_status: :active)
    reader.bookshelf_entries.create!(book: book)
    sign_in reader
    get book_path(book, group_id: group.id, return_to: group_path(group))
    expect(back_link["href"]).to eq(group_path(group))
    expect(Nokogiri::HTML(response.body).at_css("select[name='jjaek[group_id]'] option[selected]")["value"]).to eq(group.id.to_s)
  end

  it "rejects external, inaccessible shelf, and inaccessible group search origins" do
    private_shelf = other.bookshelves.default_first.first
    group = Group.create!(name: "Private", group_admin: other, group_type: :private_group, lifecycle_status: :active)
    sign_in reader
    origins = [ "https://example.invalid", user_library_path(other, bookshelf_id: private_shelf.id),
                user_library_path(reader, bookshelf_id: private_shelf.id), book_search_path(group_id: group.id), book_path(book) ]
    origins.each do |origin|
      get book_path(book, return_to: origin)
      expect(back_link["href"]).to eq(user_library_path(reader))
    end
  end

  it "provides a book fallback and retains the validated context in the legacy shelf edit form" do
    entry = reader.bookshelf_entries.create!(book: book)
    origin = user_library_path(reader, bookshelf_id: entry.bookshelf_id, sort: "recent")
    sign_in reader
    get edit_bookshelf_entry_path(entry)
    expect(back_link["href"]).to eq(book_path(book))
    get edit_bookshelf_entry_path(entry, return_to: origin)
    expect(back_link["href"]).to eq(origin)
    expect(Nokogiri::HTML(response.body).at_css("input[name='return_to']")["value"]).to eq(origin)
    patch bookshelf_entry_path(entry), params: { return_to: origin, bookshelf_entry: { status: "reading" } }
    expect(response).to redirect_to(book_path(book, return_to: origin))
  end
end
