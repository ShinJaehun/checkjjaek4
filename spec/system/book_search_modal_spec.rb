require "rails_helper"

RSpec.describe "Book search modal", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Modal reader", email: "modal-system@example.com", password: "password123!") }
  let!(:group) { Group.create!(name: "Modal club", group_admin: user, group_type: :private_group, lifecycle_status: :active) }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 900 ]
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  it "opens from navigation, focuses search, closes with button or Escape, and restores focus" do
    visit root_path
    opener = find("header a[data-book-search-modal]")
    opener.click
    expect(page).to have_css("dialog[open]")
    expect(page).to have_field(I18n.t("book_search.form.query"))
    expect(page).to have_css("dialog input[name='query']:focus")
    expect(page.evaluate_script("document.querySelector('dialog').getBoundingClientRect().right <= window.innerWidth")).to be(true)
    within("dialog") { click_button I18n.t("search_ui.close") }
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_css("header a[data-book-search-modal]:focus")
    opener.click
    expect(page).to have_css("dialog[open]")
    page.send_keys :escape
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_css("header a[data-book-search-modal]:focus")
  end

  it "selects a stored book despite external failure, keeps club context, and defaults to club posting" do
    book = Book.create!(title: "Stored modal book")
    user.bookshelf_entries.create!(book: book)
    allow(BookSearches::SearchService).to receive(:call).and_raise(BookSearches::KakaoAdapter::Error)
    visit group_path(group)
    find("a[data-book-search-modal][href='#{book_search_path(group_id: group.id)}']", match: :first).click
    within("dialog") do
      fill_in I18n.t("book_search.form.query"), with: "Stored modal"
      click_button I18n.t("book_search.form.submit")
      expect(page).to have_text(I18n.t("search_ui.external_unavailable"))
      click_link I18n.t("book_search.actions.open_internal")
    end
    expect(page).to have_current_path(book_path(book, group_id: group.id))
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_group_book"), visible: :all)
    expect(page).to have_select(I18n.t("jjaeks.form.posting_group"), selected: group.name)
  end

  it "previews and registers a partial external result before offering the club book form" do
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "New modal book", url: "https://example.com/new-modal" } ],
      meta: { pageable_count: 1, is_end: true }
    )
    visit group_path(group)
    find("a[data-book-search-modal]", match: :first).click
    within("dialog") do
      fill_in I18n.t("book_search.form.query"), with: "New modal"
      click_button I18n.t("book_search.form.submit")
      click_link I18n.t("book_search.actions.open_internal")
    end
    expect(page).to have_current_path(%r{\A/books/lookup}, ignore_query: true)
    expect(Book.find_by(title: "New modal book")).to be_nil
    click_button I18n.t("bookshelf_entries.new.title")
    expect(page).to have_current_path(%r{\A/books/\d+}, ignore_query: true)
    book = Book.find_by!(title: "New modal book")
    expect(page).to have_current_path(book_path(book, group_id: group.id))
    expect(page).to have_checked_field(I18n.t("jjaeks.actions.publish_group_book"), visible: :all)
  end
end
