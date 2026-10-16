require "rails_helper"

RSpec.describe "Standalone book search", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Search reader", email: "search-system@example.com", password: "password123!") }
  let!(:group) { Group.create!(name: "Search club", group_admin: user, group_type: :private_group, lifecycle_status: :active) }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 900 ]
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  def expect_search_path(query:, page_number: nil)
    expected_query = {
      "group_id" => group.id.to_s,
      "query" => query,
      "search_origin" => group_path(group)
    }
    expected_query["page"] = page_number.to_s if page_number

    expected_query.each do |key, value|
      parameter = "#{key}=#{Rack::Utils.escape(value)}"
      expect(page).to have_current_path(
        %r{\A#{Regexp.escape(book_search_path)}\?(?:[^&]*&)*#{Regexp.escape(parameter)}(?:&|\z)}
      )
    end
    expect(Rack::Utils.parse_query(URI.parse(page.current_url).query)).to eq(expected_query)
  end

  it "opens the search page without a query and writes a personal book jjaek for a shelved book" do
    book = Book.create!(title: "Personal search book")
    user.bookshelf_entries.create!(book: book)
    counts = [Book.count, BookshelfEntry.count]
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })

    visit root_path
    click_link I18n.t("book_search.nav"), match: :first
    expect(page).to have_current_path(book_search_path(search_origin: root_path))
    expect(page).to have_field(I18n.t("book_search.form.query"), with: "")
    expect(page).to have_no_text(I18n.t("book_search.empty.title"))
    fill_in I18n.t("book_search.form.query"), with: "Personal search"
    click_button I18n.t("book_search.form.submit")
    expect(page).to have_text(I18n.t("book_search.actions.in_shelf"))
    expect(page).to have_no_button(I18n.t("book_search.actions.add_to_shelf"))
    click_link I18n.t("book_search.actions.open_internal")
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_book"), visible: :all)
    expect([Book.count, BookshelfEntry.count]).to eq(counts)
    fill_in I18n.t("jjaeks.form.book_jjaek_content"), with: "Personal search reading note"
    click_button I18n.t("jjaeks.actions.publish_book")
    expect(page).to have_text("Personal search reading note")
    post = user.jjaeks.find_by!(content: "Personal search reading note")
    expect(post.book).to eq(book)
    expect(post.group).to be_nil
  end

  it "searches again from page two without losing the original club origin" do
    11.times { |index| Book.create!(title: "Paged repeat #{index}") }
    Book.create!(title: "Replacement book")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    visit group_path(group)
    click_link I18n.t("book_search.nav"), match: :first
    fill_in I18n.t("book_search.form.query"), with: "Paged repeat"
    click_button I18n.t("book_search.form.submit")
    expect_search_path(query: "Paged repeat")
    expect(page).to have_css("article", count: 10)
    click_link I18n.t("book_search.pagination.next")
    expect_search_path(query: "Paged repeat", page_number: 2)
    expect(page).to have_field(I18n.t("book_search.form.query"), with: "Paged repeat")
    fill_in I18n.t("book_search.form.query"), with: "Replacement"
    click_button I18n.t("book_search.form.submit")
    expect_search_path(query: "Replacement")
    expect(page).to have_text("Replacement book")
    expect(page).to have_text(I18n.t("book_search.pagination.page", page: 1))
    click_link I18n.t("book_search.actions.open_internal")
    search_path = book_search_path(query: "Replacement", page: 1, group_id: group.id, search_origin: group_path(group))
    expect(page).to have_link(I18n.t("jjaeks.actions.back"), href: search_path)
    find("a[data-back-link]").click
    expect(page).to have_current_path(search_path)
    find("a[data-back-link]").click
    expect(page).to have_current_path(group_path(group))
  end

  it "selects a stored book despite external failure, keeps club context, and defaults to club posting" do
    book = Book.create!(title: "Stored search book")
    user.bookshelf_entries.create!(book: book)
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)
    search_path = book_search_path(group_id: group.id, page: 1, query: "Stored search", search_origin: group_path(group))
    visit group_path(group)
    find("a[href='#{book_search_path(group_id: group.id, search_origin: group_path(group))}']", match: :first).click
    fill_in I18n.t("book_search.form.query"), with: "Stored search"
    click_button I18n.t("book_search.form.submit")
    expect(page).to have_text(I18n.t("search_ui.external_unavailable"))
    click_link I18n.t("book_search.actions.open_internal")
    expect(page).to have_current_path(
      book_path(book, group_id: group.id, return_to: search_path)
    )
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_group_book"), visible: :all)
    expect(page).to have_select(I18n.t("jjaeks.form.posting_group"), selected: group.name)
    find("a[data-back-link]").click
    expect(page).to have_current_path(search_path)
    expect(page).to have_field(I18n.t("book_search.form.query"), with: "Stored search")
    find("a[data-back-link]").click
    expect(page).to have_current_path(group_path(group))
  end

  it "previews and registers a partial external result before offering the club book form" do
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "New search book", url: "https://example.com/new-search" } ],
      meta: { pageable_count: 1, is_end: true }
    )
    search_path = book_search_path(group_id: group.id, page: 1, query: "New search", search_origin: group_path(group))
    visit group_path(group)
    click_link I18n.t("book_search.nav"), match: :first
    fill_in I18n.t("book_search.form.query"), with: "New search"
    click_button I18n.t("book_search.form.submit")
    click_link I18n.t("book_search.actions.open_internal")
    expect(page).to have_current_path(%r{\A/books/lookup}, ignore_query: true)
    expect(Book.find_by(title: "New search book")).to be_nil
    click_button I18n.t("bookshelf_entries.new.title")
    expect(page).to have_current_path(%r{\A/books/\d+}, ignore_query: true)
    book = Book.find_by!(title: "New search book")
    expect(page).to have_current_path(
      book_path(book, group_id: group.id, return_to: search_path)
    )
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_group_book"), visible: :all)
    find("a[data-back-link]").click
    expect(page).to have_current_path(search_path)
    find("a[data-back-link]").click
    expect(page).to have_current_path(group_path(group))
  end
end
