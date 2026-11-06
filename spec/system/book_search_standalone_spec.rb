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
    within("header[data-controller='mobile-navigation']") { click_button I18n.t("book_search.nav") }
    expect(page).to have_css("#global-book-search-dialog[open]")
    expect(page).to have_css("#global-book-search-query:focus")
  end

  def open_attachment_search
    within("#jjaek-composer") { click_button I18n.t("jjaek_books.add") }
    expect(page).to have_current_path(group_path(group))
    expect(page).to have_css("#recommendation-window")
    expect(page).to have_css("#recommendation-window #recommendation-query")
    expect(page).to have_css("#jjaek-composer[data-group-id='#{group.id}'] form[action='#{group_jjaeks_path(group)}']")
  end

  def search_attachments(query)
    within("#recommendation-window") do
      fill_in "recommendation-query", with: query
      click_button I18n.t("book_search.form.submit")
    end
  end

  def expect_attachment_search(query:, page_number: 1, book_ids: [])
    expect(page).to have_current_path(book_search_path, ignore_query: true)
    expect(page).to have_css("#recommendation-search-results [data-recommendation-results-state][data-query='#{query}'][data-page='#{page_number}']", visible: :all)
    expect(page).to have_field("recommendation-query", with: query)
    parameters = Rack::Utils.parse_nested_query(URI.parse(page.current_url).query)
    expect(parameters).to include("attachment" => "1", "group_id" => group.id.to_s,
                                  "query" => query, "search_origin" => group_path(group))
    expect(parameters.fetch("page", "1")).to eq(page_number.to_s)
    expect(parameters.fetch("selected_books").reject(&:empty?)).to eq(book_ids.map(&:to_s))
  end

  def expect_composer(book:, group_context: nil)
    destination = group_context ? group_jjaeks_path(group_context) : jjaeks_path
    expect(page).to have_css("#jjaek-publish-form[action='#{destination}'] textarea[name='jjaek[content]']")
    expect(page).to have_css("#jjaek-attached-books input[name='selected_books[]'][value='#{book.id}'][form='jjaek-publish-form']", visible: :all)
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{book.id}']", text: book.title)
    if group_context
      expect(page).to have_css("#jjaek-composer[data-group-id='#{group_context.id}']")
      expect(page).to have_no_css("#jjaek-publish-form [name='jjaek[visibility]']", visible: :all)
    else
      expect(page).to have_checked_field(I18n.t("jjaeks.visibility.public_jjaek"), visible: :all)
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

  it "searches globally and writes a personal Jjaek with the selected book on the common form" do
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
    expect_composer(book:)
    expect([ Book.count, BookshelfEntry.count ]).to eq(counts)
    fill_in "jjaek[content]", with: "Personal search reading note"
    within("#jjaek-composer") { click_button I18n.t("jjaeks.actions.publish_short") }
    expect(page).to have_text("Personal search reading note")
    post = user.jjaeks.find_by!(content: "Personal search reading note")
    expect(post.attached_books).to eq([book])
    expect(post.group).to be_nil
    expect([ Book.count, BookshelfEntry.count ]).to eq(counts)
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
    expect_composer(book:)
    find("a[data-back-link]").click
    expect(page).to have_current_path(search_path)
    find("a[data-back-link]").click
    expect(page).to have_current_path(group_path(group))
  end

  [ 390, 1280 ].each do |width|
    it "reuses the global dialog from the library and returns to its shelf at #{width}px" do
      shelf = user.bookshelves.create!(name: "Library search shelf", visibility: :private)
      book = Book.create!(title: "Library modal book")
      user.bookshelf_entries.create!(book: book, bookshelf: shelf)
      origin = user_library_path(user, bookshelf_id: shelf.id, sort: "title")
      allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
      page.driver.browser.manage.window.resize_to(width, 900)
      visit origin

      find("main button[aria-controls='global-book-search-dialog']").click
      expect(page).to have_current_path(origin)
      expect(page).to have_css("#global-book-search-dialog", count: 1, visible: :all)
      expect(page).to have_css("#global-book-search-dialog[open]")
      expect(page).to have_css("#global-book-search-query:focus")
      within("#global-book-search-dialog") { click_button I18n.t("book_search.actions.close") }
      expect(page).to have_no_css("#global-book-search-dialog[open]")
      expect(page).to have_css("main button[aria-controls='global-book-search-dialog']:focus")

      find("main button[aria-controls='global-book-search-dialog']").click
      expect(page).to have_css("#global-book-search-query:focus")
      find("#global-book-search-query").send_keys(:escape)
      expect(page).to have_no_css("#global-book-search-dialog[open]")
      expect(page).to have_css("main button[aria-controls='global-book-search-dialog']:focus")
      expect(page).to have_no_css("body[style*='overflow: hidden']")

      open_global_search
      within("#global-book-search-dialog") { click_button I18n.t("book_search.actions.close") }
      expect(page).to have_no_css("#global-book-search-dialog[open]")
      find("main button[aria-controls='global-book-search-dialog']").click
      fill_in I18n.t("book_search.form.query"), with: "Library modal"
      click_button I18n.t("book_search.form.submit")
      expect(page).to have_current_path(book_search_path, ignore_query: true)
      expect(Rack::Utils.parse_query(URI.parse(page.current_url).query)).to eq(
        "query" => "Library modal", "search_origin" => origin
      )
      page.go_back
      expect(page).to have_current_path(origin)
      expect(page).to have_no_css("#global-book-search-dialog[open]")
      expect(page).to have_no_css("body[style*='overflow: hidden']")

      find("main button[aria-controls='global-book-search-dialog']").click
      expect(page).to have_css("#global-book-search-query:focus")
      fill_in I18n.t("book_search.form.query"), with: "Library modal"
      click_button I18n.t("book_search.form.submit")
      expect(page).to have_current_path(book_search_path, ignore_query: true)
      click_link I18n.t("book_search.actions.open_internal")
      results_path = book_search_path(query: "Library modal", page: 1, search_origin: origin)
      expect(page).to have_current_path(book_path(book, return_to: results_path))
      expect_composer(book:)
      find("a[data-back-link]").click
      expect(page).to have_current_path(results_path)
      find("a[data-back-link]").click
      expect(page).to have_current_path(origin)
    end

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

  [390, 1280].each do |width|
    it "keeps the Group draft and selected books through paging and repeat searches at #{width}px" do
      books = Array.new(11) { |index| Book.create!(title: "Paged repeat #{index}") }
      replacement = Book.create!(title: "Replacement book")
      counts = [Book.count, BookshelfEntry.count, Jjaek.count]
      allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
      page.driver.browser.manage.window.resize_to(width, 900)
      visit group_path(group)
      fill_in "jjaek[content]", with: "Group draft survives"
      open_attachment_search
      expect(page.evaluate_script(<<~JS)).to be(true)
        (() => {
          const bounds = document.getElementById("recommendation-window").getBoundingClientRect()
          return bounds.left >= 0 && bounds.right <= window.innerWidth && bounds.top >= 0 && bounds.bottom <= window.innerHeight
        })()
      JS
      search_attachments("Paged repeat")
      expect_attachment_search(query: "Paged repeat")
      within("#recommendation-search-results") do
        expect(page).to have_css("article", count: 10)
        within("article[data-book-id='#{books.first.id}']") do
          click_button I18n.t("jjaek_books.choose")
          expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
        end
        click_link I18n.t("book_search.pagination.next")
      end
      expect_attachment_search(query: "Paged repeat", page_number: 2, book_ids: [books.first.id])
      within("#recommendation-window") { expect(page).to have_text(books.first.title) }
      search_attachments("Replacement")
      expect_attachment_search(query: "Replacement", book_ids: [books.first.id])
      within("#recommendation-search-results") do
        expect(page).to have_text(I18n.t("book_search.pagination.page", page: 1))
        within("article[data-book-id='#{replacement.id}']") do
          click_button I18n.t("jjaek_books.choose")
          expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
        end
      end
      within("#recommendation-window") { click_button I18n.t("recommendations.finish_selection") }
      expect(page).to have_current_path(group_path(group))
      expect(page).to have_no_css("#recommendation-window")
      expect(page).to have_field("jjaek[content]", with: "Group draft survives")
      expect_composer(book: books.first, group_context: group)
      expect_composer(book: replacement, group_context: group)
      expect(page.all("#jjaek-attached-books input[name='selected_books[]']", visible: :all).map(&:value))
        .to eq(["", books.first.id.to_s, replacement.id.to_s])
      expect([Book.count, BookshelfEntry.count, Jjaek.count]).to eq(counts)

      open_global_search
      within("#global-book-search-dialog") do
        expect(page).to have_field(I18n.t("book_search.form.query"), with: "")
        expect(page).to have_no_css("input[name='group_id']", visible: :all)
        click_button I18n.t("book_search.actions.close")
      end
      expect(page).to have_field("jjaek[content]", with: "Group draft survives")
      open_attachment_search
      within("#recommendation-window") do
        expect(page).to have_text(books.first.title, count: 1)
        expect(page).to have_text(replacement.title, count: 1)
        click_button I18n.t("recommendations.finish_selection")
      end
      expect(page).to have_no_css("#recommendation-window")
    end
  end

  it "attaches a stored book despite external failure and publishes in the original Group" do
    book = Book.create!(title: "Stored search book")
    counts = [Book.count, BookshelfEntry.count]
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)
    visit group_path(group)
    fill_in "jjaek[content]", with: "Group note despite external failure"
    open_attachment_search
    search_attachments("Stored search")
    expect_attachment_search(query: "Stored search")
    within("#recommendation-search-results") do
      expect(page).to have_text(I18n.t("search_ui.external_unavailable"))
      within("article[data-book-id='#{book.id}']") do
        click_button I18n.t("jjaek_books.choose")
        expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
      end
    end
    within("#recommendation-window") { click_button I18n.t("recommendations.finish_selection") }
    expect(page).to have_current_path(group_path(group))
    expect_composer(book:, group_context: group)
    expect(page).to have_field("jjaek[content]", with: "Group note despite external failure")
    within("#jjaek-composer") { click_button I18n.t("jjaeks.actions.publish_short") }
    expect(page).to have_css("#feed-items article", text: "Group note despite external failure")
    post = user.jjaeks.find_by!(content: "Group note despite external failure")
    expect(post.group).to eq(group)
    expect(post.attached_books).to eq([book])
    expect([Book.count, BookshelfEntry.count]).to eq(counts)
    within("#jjaek_#{post.id}") { expect(page).to have_link(book.title) }
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

  it "selects a bookshelf and updates only the card while keeping the global search context" do
    shelf = user.bookshelves.create!(name: "모바일에서도 줄바꿈하는 긴 책장 이름" * 3, visibility: :private)
    stored_book = Book.create!(title: "Shelf selection stored")
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "Shelf selection external", url: "https://example.com/shelf-selection" } ],
      meta: { is_end: true }
    )
    visit root_path
    open_global_search
    fill_in I18n.t("book_search.form.query"), with: "Shelf selection"
    click_button I18n.t("book_search.form.submit")
    search_path = book_search_path(query: "Shelf selection", search_origin: root_path)
    expect_search_url(search_path)
    card = find("article", text: "Shelf selection external")
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
    within(find("article", text: stored_book.title)) { expect(page).to have_button(I18n.t("book_search.actions.add_to_shelf")) }
    entry = user.bookshelf_entries.find_by!(book: Book.find_by!(title: "Shelf selection external"))
    expect(entry.bookshelf).to eq(shelf)
    expect(entry.book_activities.where(action: :added_to_shelf).count).to eq(1)
    return_path = book_search_path(query: "Shelf selection", page: 1, search_origin: root_path)
    within("##{card_id}") do
      expect(page).to have_link(I18n.t("book_search.actions.open_internal"), href: book_path(entry.book, return_to: return_path))
    end
  end

  it "registers an external attachment in a chosen shelf without losing the Group draft or other attachments" do
    # External attachment tokens must survive across selection and publication requests.
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    shelf = user.bookshelves.create!(name: "모바일에서도 줄바꿈하는 긴 책장 이름" * 3, visibility: :private)
    stored_book = Book.create!(title: "Shelf selection stored")
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "Shelf selection external", url: "https://example.com/shelf-selection" } ],
      meta: { is_end: true }
    )
    visit group_path(group)
    fill_in "jjaek[content]", with: "Group attachment shelf draft"
    open_attachment_search
    search_attachments("Shelf selection")
    expect_attachment_search(query: "Shelf selection")
    within("#recommendation-search-results") do
      expect(page).to have_css("article", count: 2)
      ["Shelf selection external", stored_book.title].each do |title|
        within(find("article", text: title)) do
          click_button I18n.t("jjaek_books.choose")
          expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
        end
      end
    end
    within("#recommendation-window") { click_button I18n.t("recommendations.finish_selection") }
    expect(page).to have_current_path(group_path(group))
    expect_composer(book: stored_book, group_context: group)
    expect(Book.find_by(title: "Shelf selection external")).to be_nil
    expect(user.bookshelf_entries).to be_empty
    row = find("#jjaek-attached-books [data-book-key]", text: "Shelf selection external")
    row_key = row["data-book-key"]
    dialog_id = row.find("button", text: I18n.t("jjaek_books.add_to_shelf"))["aria-controls"]
    within(row) { click_button I18n.t("jjaek_books.add_to_shelf") }
    within("##{dialog_id}") do
      expect(page).to have_checked_field(user.default_bookshelf.name)
      find("input[type='radio'][checked]").send_keys(:escape)
    end
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_css("button[aria-controls='#{dialog_id}']:focus")
    expect(page).to have_field("jjaek[content]", with: "Group attachment shelf draft")
    within(row) { click_button I18n.t("jjaek_books.add_to_shelf") }
    within("##{dialog_id}") do
      choose shelf.name
      click_button I18n.t("book_search.actions.add_to_shelf")
    end
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_no_css("body[style*='overflow: hidden']")
    expect(page).to have_current_path(group_path(group))
    expect(page).to have_field("jjaek[content]", with: "Group attachment shelf draft")
    within("#jjaek-attached-books [data-book-key='#{row_key}']") do
      expect(page).to have_button(I18n.t("book_search.actions.in_bookshelf", bookshelf_name: shelf.name), disabled: true)
      expect(page).to have_no_button(I18n.t("jjaek_books.add_to_shelf"))
    end
    within("#jjaek-attached-books [data-book-key='#{stored_book.id}']") do
      expect(page).to have_button(I18n.t("jjaek_books.add_to_shelf"))
    end
    external_book = Book.find_by!(title: "Shelf selection external")
    entry = user.bookshelf_entries.find_by!(book: external_book)
    expect(entry.bookshelf).to eq(shelf)
    expect(entry.book_activities.where(action: :added_to_shelf).count).to eq(1)
    expect(user.bookshelf_entries.exists?(book: stored_book)).to be(false)
    expect(user.jjaeks.where(content: "Group attachment shelf draft")).to be_empty
    expect_composer(book: stored_book, group_context: group)
    within("#jjaek-composer") { click_button I18n.t("jjaeks.actions.publish_short") }
    expect(page).to have_css("#feed-items article", text: "Group attachment shelf draft")
    post = user.jjaeks.find_by!(content: "Group attachment shelf draft")
    expect(post.group).to eq(group)
    expect(post.attached_books).to eq([external_book, stored_book])
    expect(Book.where(title: external_book.title).count).to eq(1)
  end

  it "previews and registers an external result globally and keeps the Group as its return origin" do
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "New search book", url: "https://example.com/new-search" } ],
      meta: { pageable_count: 1, is_end: true }
    )
    search_path = book_search_path(page: 1, query: "New search", search_origin: group_path(group))
    visit group_path(group)
    open_global_search
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
      book_path(book, return_to: search_path)
    )
    expect_composer(book:)
    expect(page).to have_no_css("#jjaek-publish-form [name='jjaek[group_id]']", visible: :all)
    find("a[data-back-link]").click
    expect(page).to have_current_path(search_path)
    find("a[data-back-link]").click
    expect(page).to have_current_path(group_path(group))
  end
end
