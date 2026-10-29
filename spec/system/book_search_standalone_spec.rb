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

  def open_global_search
    if page.has_button?(I18n.t("navigation.menu"), visible: true)
      click_button I18n.t("navigation.menu")
    end
    within("header") { click_button I18n.t("book_search.nav") }
    expect(page).to have_css("#global-book-search-dialog[open]")
    expect(page).to have_css("#global-book-search-query:focus")
  end

  def open_club_search
    within("main") { click_button I18n.t("groups.jjaeks.tabs.book") }
    expect(page).to have_current_path(group_path(group))
    expect(page).to have_css("#group-book-search-dialog[open]")
    expect(page).to have_css("#group-book-search-query:focus")
    within("#group-book-search-dialog") do
      expect(page).to have_text(I18n.t("book_search.modal.group_destination", group_name: group.name))
    end
  end

  def expect_search_path(query:, page_number: nil, group_id: group.id)
    expected_query = {
      "query" => query,
      "search_origin" => group_path(group)
    }
    expected_query["group_id"] = group_id.to_s if group_id
    expected_query["page"] = page_number.to_s if page_number

    expected_query.each do |key, value|
      parameter = "#{key}=#{Rack::Utils.escape(value)}"
      expect(page).to have_current_path(
        %r{\A#{Regexp.escape(book_search_path)}\?(?:[^&]*&)*#{Regexp.escape(parameter)}(?:&|\z)}
      )
    end
    expect(Rack::Utils.parse_query(URI.parse(page.current_url).query)).to eq(expected_query)
  end

  def expect_search_url(expected_path)
    expected_uri = URI.parse(expected_path)
    expect(page).to have_current_path(expected_uri.path, ignore_query: true)
    expect(Rack::Utils.parse_query(URI.parse(page.current_url).query)).to eq(
      Rack::Utils.parse_query(expected_uri.query)
    )
  end

  it "searches from the global dialog and writes a personal book jjaek for a shelved book" do
    book = Book.create!(title: "Personal search book")
    user.bookshelf_entries.create!(book: book)
    counts = [ Book.count, BookshelfEntry.count ]
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })

    visit root_path
    open_global_search
    expect(page).to have_current_path(root_path)
    expect(page).to have_field(I18n.t("book_search.form.query"), with: "")
    expect(page).to have_no_text(I18n.t("book_search.empty.title"))
    fill_in I18n.t("book_search.form.query"), with: "Personal search"
    click_button I18n.t("book_search.form.submit")
    expect(page).to have_current_path(book_search_path, ignore_query: true)
    expect(Rack::Utils.parse_query(URI.parse(page.current_url).query)).to eq(
      "query" => "Personal search",
      "search_origin" => root_path
    )
    expect(page).to have_no_css("#global-book-search-dialog[open]")
    expect(page).to have_text(I18n.t("book_search.actions.in_shelf"))
    expect(page).to have_no_button(I18n.t("book_search.actions.add_to_shelf"))
    click_link I18n.t("book_search.actions.open_internal")
    expect(page).to have_css("#book-jjaek-form form")
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_book"), visible: :all)
    expect([ Book.count, BookshelfEntry.count ]).to eq(counts)
    fill_in I18n.t("jjaeks.form.book_jjaek_content"), with: "Personal search reading note"
    within("#book-jjaek-form") do
      click_button I18n.t("jjaeks.actions.publish_book")
    end
    expect(page).to have_text("Personal search reading note")
    post = user.jjaeks.find_by!(content: "Personal search reading note")
    expect(post.book).to eq(book)
    expect(post.group).to be_nil
  end

  it "keeps global club searches personal through pagination, repeat searches, and return navigation" do
    11.times { |index| Book.create!(title: "Paged global #{index}") }
    book = Book.create!(title: "Replacement global book")
    user.bookshelf_entries.create!(book: book)
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })

    visit group_path(group)
    open_global_search
    fill_in I18n.t("book_search.form.query"), with: "Paged global"
    click_button I18n.t("book_search.form.submit")
    expect_search_path(query: "Paged global", group_id: nil)
    click_link I18n.t("book_search.pagination.next")
    expect_search_path(query: "Paged global", page_number: 2, group_id: nil)
    fill_in I18n.t("book_search.form.query"), with: "Replacement global"
    click_button I18n.t("book_search.form.submit")
    expect_search_path(query: "Replacement global", group_id: nil)
    click_link I18n.t("book_search.actions.open_internal")
    search_path = book_search_path(query: "Replacement global", page: 1, search_origin: group_path(group))
    expect(page).to have_current_path(book_path(book, return_to: search_path))
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_book"), visible: :all)
    find("a[data-back-link]").click
    expect(page).to have_current_path(search_path)
    find("a[data-back-link]").click
    expect(page).to have_current_path(group_path(group))
  end

  [ 390, 1280 ].each do |width|
    it "closes and restores focus and Turbo cache correctly at #{width}px" do
      allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
      page.driver.browser.manage.window.resize_to(width, 900)
      visit root_path
      if width < 1024
        open_global_search
        focus_selector = "header button[data-mobile-navigation-target='button']:focus"
      else
        within("header") { click_button I18n.t("book_search.nav") }
        focus_selector = "header button[aria-controls='global-book-search-dialog']:focus"
      end
      expect(page).to have_css("#global-book-search-query:focus")
      expect(page).to have_css("body[style*='overflow: hidden']")
      expect(page).to have_css("header button[data-mobile-navigation-target='button'][aria-expanded='false']", visible: :all)
      find("#global-book-search-query").send_keys(:escape)
      expect(page).to have_no_css("#global-book-search-dialog[open]")
      expect(page).to have_no_css("body[style*='overflow: hidden']")
      expect(page).to have_css(focus_selector)

      click_button I18n.t("navigation.menu") if width < 1024
      within("header") { click_button I18n.t("book_search.nav") }
      within("#global-book-search-dialog") { click_button I18n.t("book_search.actions.close") }
      expect(page).to have_no_css("#global-book-search-dialog[open]")
      expect(page).to have_css(focus_selector)

      click_button I18n.t("navigation.menu") if width < 1024
      within("header") { click_button I18n.t("book_search.nav") }
      fill_in I18n.t("book_search.form.query"), with: "Cached search"
      click_button I18n.t("book_search.form.submit")
      expect(page).to have_current_path(book_search_path, ignore_query: true)
      expect(Rack::Utils.parse_query(URI.parse(page.current_url).query)).to eq(
        "query" => "Cached search",
        "search_origin" => root_path
      )
      page.go_back
      expect(page).to have_current_path(root_path)
      expect(page).to have_no_css("#global-book-search-dialog[open]")
      expect(page).to have_no_css("body[style*='overflow: hidden']")
      click_button I18n.t("navigation.menu") if width < 1024
      within("header") { click_button I18n.t("book_search.nav") }
      expect(page).to have_css("#global-book-search-query:focus")
    end
  end

  it "searches again from page two without losing the original club origin" do
    11.times { |index| Book.create!(title: "Paged repeat #{index}") }
    Book.create!(title: "Replacement book")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    visit group_path(group)
    open_club_search
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

  it "closes the club dialog, restores its opener, and keeps global search separate" do
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    visit group_path(group)
    open_club_search
    fill_in I18n.t("book_search.form.query"), with: "Club draft"
    find("#group-book-search-query").send_keys(:escape)
    expect(page).to have_no_css("#group-book-search-dialog[open]")
    expect(page).to have_css("button[aria-controls='group-book-search-dialog']:focus")
    expect(page).to have_no_css("body[style*='overflow: hidden']")

    open_global_search
    within("#global-book-search-dialog") do
      expect(page).to have_field(I18n.t("book_search.form.query"), with: "")
      expect(page).to have_no_text(I18n.t("book_search.modal.group_destination", group_name: group.name))
      click_button I18n.t("book_search.actions.close")
    end
    expect(page).to have_no_css("#global-book-search-dialog[open]")
    open_club_search
    expect(page).to have_field(I18n.t("book_search.form.query"), with: "Club draft")
    within("#group-book-search-dialog") { click_button I18n.t("book_search.actions.close") }
    expect(page).to have_no_css("#group-book-search-dialog[open]")
    expect(page).to have_css("button[aria-controls='group-book-search-dialog']:focus")
    open_club_search
    fill_in I18n.t("book_search.form.query"), with: "Club cached"
    click_button I18n.t("book_search.form.submit")
    expect_search_path(query: "Club cached")
    page.go_back
    expect(page).to have_current_path(group_path(group))
    expect(page).to have_no_css("#group-book-search-dialog[open]")
    expect(page).to have_no_css("body[style*='overflow: hidden']")
    open_club_search
  end

  it "selects a stored book despite external failure, keeps club context, and defaults to club posting" do
    book = Book.create!(title: "Stored search book")
    user.bookshelf_entries.create!(book: book)
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)
    search_path = book_search_path(group_id: group.id, page: 1, query: "Stored search", search_origin: group_path(group))
    visit group_path(group)
    open_club_search
    fill_in I18n.t("book_search.form.query"), with: "Stored search"
    click_button I18n.t("book_search.form.submit")
    expect(page).to have_text(I18n.t("search_ui.external_unavailable"))
    click_link I18n.t("book_search.actions.open_internal")
    expect(page).to have_current_path(
      book_path(book, group_id: group.id, return_to: search_path)
    )
    expect(page).to have_css("#book-jjaek-form form")
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_group_book"), visible: :all)
    expect(page).to have_select(I18n.t("jjaeks.form.posting_group"), selected: group.name)
    expect(page).to have_no_css("#book-writing-dialog")
    choose I18n.t("jjaeks.actions.publish_book"), allow_label_click: true
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_book"), visible: :all)
    expect(page).to have_no_select(I18n.t("jjaeks.form.posting_group"))
    find("a[data-back-link]").click
    expect(page).to have_current_path(search_path)
    expect(page).to have_field(I18n.t("book_search.form.query"), with: "Stored search")
    find("a[data-back-link]").click
    expect(page).to have_current_path(group_path(group))
    expect(page).to have_no_css("#group-book-search-dialog[open]")
  end

  it "adds directly to the default shelf without a dialog when there is only one bookshelf" do
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "Single shelf result", url: "https://example.com/single-shelf-result" } ],
      meta: { is_end: true }
    )
    visit root_path
    open_global_search
    fill_in I18n.t("book_search.form.query"), with: "Single shelf"
    click_button I18n.t("book_search.form.submit")
    search_path = book_search_path(query: "Single shelf", search_origin: root_path)
    expect_search_url(search_path)

    within("article") do
      expect(page).to have_no_css("dialog", visible: :all)
      click_button I18n.t("book_search.actions.add_to_shelf")
      expect(page).to have_button(I18n.t("book_search.actions.in_shelf"), disabled: true)
    end
    expect_search_url(search_path)
    book = Book.find_by!(title: "Single shelf result")
    expect(user.bookshelf_entries.find_by!(book: book).bookshelf).to eq(user.default_bookshelf)
  end

  [ :global, :club ].each do |context|
    it "selects a bookshelf and updates only the card while keeping the #{context} search context" do
      shelf = user.bookshelves.create!(name: "모바일에서도 줄바꿈하는 긴 책장 이름" * 3, visibility: :private)
      stored_book = Book.create!(title: "Shelf selection stored")
      allow(BookSearches::SearchService).to receive(:call).and_return(
        results: [ { title: "Shelf selection external", url: "https://example.com/shelf-selection" } ],
        meta: { is_end: true }
      )
      origin = context == :club ? group_path(group) : root_path
      visit origin
      context == :club ? open_club_search : open_global_search
      fill_in I18n.t("book_search.form.query"), with: "Shelf selection"
      click_button I18n.t("book_search.form.submit")
      search_path = book_search_path(query: "Shelf selection", group_id: (group.id if context == :club), search_origin: origin)
      expect_search_url(search_path)
      title = context == :club ? stored_book.title : "Shelf selection external"
      card = find("article", text: title)
      card_id = card["id"]
      dialog_id = "#{card_id}_shelf_dialog"
      within(card) { click_button I18n.t("book_search.actions.add_to_shelf") }
      expect(page).to have_css("dialog[open]", count: 1)
      within("##{dialog_id}") do
        expect(page).to have_checked_field(user.default_bookshelf.name)
        find("input[type='radio'][checked]").send_keys(:escape)
      end
      expect(page).to have_no_css("dialog[open]")
      expect(page).to have_css("button[aria-controls='#{dialog_id}']:focus")
      within("##{card_id}") { click_button I18n.t("book_search.actions.add_to_shelf") }
      within("##{dialog_id}") do
        choose shelf.name
        click_button I18n.t("book_search.actions.add_to_shelf")
      end

      within("##{card_id}") do
        expect(page).to have_button(I18n.t("book_search.actions.in_bookshelf", bookshelf_name: shelf.name), disabled: true)
        expect(page).to have_no_button(I18n.t("book_search.actions.add_to_shelf"))
      end
      expect_search_url(search_path)
      expect(page).to have_no_css("dialog[open]")
      expect(page).to have_no_css("body[style*='overflow: hidden']")
      expect(page).to have_css("article", count: 2)
      other_title = context == :club ? "Shelf selection external" : stored_book.title
      within(find("article", text: other_title)) { expect(page).to have_button(I18n.t("book_search.actions.add_to_shelf")) }
      entry = user.bookshelf_entries.find_by!(book: Book.find_by!(title: title))
      expect(entry.bookshelf).to eq(shelf)
      expect(entry.book_activities.where(action: :added_to_shelf).count).to eq(1)
      return_path = book_search_path(query: "Shelf selection", page: 1,
                                     group_id: (group.id if context == :club), search_origin: origin)
      within("##{card_id}") do
        expect(page).to have_link(I18n.t("book_search.actions.open_internal"),
                                  href: book_path(entry.book, group_id: (group.id if context == :club), return_to: return_path))
      end
    end
  end

  it "previews and registers a partial external result before offering the club book form" do
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "New search book", url: "https://example.com/new-search" } ],
      meta: { pageable_count: 1, is_end: true }
    )
    search_path = book_search_path(group_id: group.id, page: 1, query: "New search", search_origin: group_path(group))
    visit group_path(group)
    open_club_search
    fill_in I18n.t("book_search.form.query"), with: "New search"
    click_button I18n.t("book_search.form.submit")
    click_link I18n.t("book_search.actions.open_internal")
    expect(page).to have_current_path(%r{\A/books/lookup}, ignore_query: true)
    expect(Book.find_by(title: "New search book")).to be_nil
    find("button[aria-controls='book-shelf-dialog']").click
    expect(page).to have_css("dialog#book-shelf-dialog[open]")

    within("dialog#book-shelf-dialog") do
      click_button I18n.t("bookshelf_entries.new.title")
    end

    expect(page).to have_current_path(%r{\A/books/\d+}, ignore_query: true)
    book = Book.find_by!(title: "New search book")
    expect(user.bookshelf_entries.exists?(book: book)).to be(true)

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
