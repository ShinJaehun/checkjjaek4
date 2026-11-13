require "rails_helper"

RSpec.describe "Book context composition", type: :system do
  include Warden::Test::Helpers
  let(:user) { User.create!(name: "Reader", email: "book-context-system@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "Context book") }
  let(:group) { Group.create!(name: "Club", group_admin: user, lifecycle_status: :active) }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 720 ]
    login_as user, scope: :user
  end
  after { Warden.test_reset! }

  it "keeps the Group destination when the preselected book is removed and the note is saved" do
    visit book_path(book, group_id: group.id)
    within("#book-jjaek-form") do
      expect(page).to have_no_css("[name='jjaek[visibility]']", visible: :all)
      fill_in "jjaek[content]", with: "Group note without a book"
      click_button I18n.t("jjaek_books.remove_book", title: book.title), enable_aria_label: true
      click_button I18n.t("jjaeks.actions.publish_short")
    end
    expect(page).to have_current_path(root_path, ignore_query: true)
    expect(page).to have_field("jjaek[content]", with: "")
    expect(page).to have_no_css("#jjaek-attached-books [data-book-key='#{book.id}']")
    record = group.jjaeks.find_by!(content: "Group note without a book")
    expect(record.attached_books).to be_empty
    expect(user.bookshelf_entries).to be_empty
  end

  it "preserves a book-page draft through selection and resets it after publication and a fresh Turbo visit" do
    other_book = Book.create!(title: "Additional context book", authors_text: "Additional author")
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    visit book_path(book)
    fill_in "jjaek[content]", with: "Book page draft"
    choose I18n.t("jjaeks.visibility.private_jjaek"), allow_label_click: true
    click_button I18n.t("jjaek_books.add")
    within("#book-selection-window") do
      fill_in "book-selection-query", with: other_book.title
      click_button I18n.t("book_search.form.submit")
    end
    within("#book-selection-search-results article[data-book-id='#{other_book.id}']") do
      click_button I18n.t("jjaek_books.choose")
      expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
    end
    within("#book-selection-window") { click_button I18n.t("jjaek_books.finish_selection") }
    expect(page).to have_no_css("#jjaek-composer[data-turbo-permanent]", visible: :all)
    expect(page).to have_current_path(book_path(book), ignore_query: true)
    expect(page).to have_field("jjaek[content]", with: "Book page draft")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all)
    within("#jjaek-attached-books") do
      expect(page).to have_text(book.title)
      expect(page).to have_text(other_book.title)
      expect(page).to have_text(other_book.authors_text)
    end
    click_button I18n.t("jjaeks.actions.publish_short")
    expect(page).to have_text(I18n.t("jjaeks.notices.created"))
    expect(page).to have_current_path(book_path(book), ignore_query: true)
    expect(page).to have_field("jjaek[content]", with: "")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.public_jjaek"), visible: :all)
    expect(page).to have_no_css("#jjaek-attached-books [data-book-key='#{other_book.id}']")
    record = user.jjaeks.find_by!(content: "Book page draft")
    expect(record.attached_books).to eq([ book, other_book ])
    expect(record).to be_private_jjaek

    fill_in "jjaek[content]", with: "Discard this draft"
    within("#jjaek-attached-books") { click_button I18n.t("jjaek_books.remove_book", title: book.title), enable_aria_label: true }
    within("#jjaek_#{record.id}") { click_link book.title, exact: true }
    expect(page).to have_field("jjaek[content]", with: "")
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{book.id}']")
    expect(page).to have_no_css("#jjaek-attached-books [data-book-key='#{other_book.id}']")
    expect(user.bookshelf_entries).to be_empty
  end

  it "keeps the draft and selected book while shelving its search result in a chosen bookshelf" do
    shelf = user.bookshelves.create!(name: "Search registration shelf", visibility: :private)
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
    visit book_path(book)
    fill_in "jjaek[content]", with: "Keep this draft while shelving"
    choose I18n.t("jjaeks.visibility.private_jjaek"), allow_label_click: true
    click_button I18n.t("jjaek_books.add")
    within("#book-selection-window") do
      fill_in "book-selection-query", with: book.title
      click_button I18n.t("book_search.form.submit")
    end
    expect(page).to have_css("#book-selection-search-results [data-book-id='#{book.id}']")
    search_url = page.current_url
    within("#book-selection-search-results [data-book-id='#{book.id}']") do
      expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
      click_button I18n.t("jjaek_books.add_to_shelf")
      within("dialog[open]") do
        choose shelf.name, allow_label_click: true
        click_button I18n.t("book_search.actions.add_to_shelf")
      end
      expect(page).to have_button(I18n.t("book_search.actions.in_bookshelf", bookshelf_name: shelf.name), disabled: true)
      expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
    end
    expect(page.current_url).to eq(search_url)
    within("#book-selection-window") do
      expect(page).to have_field("book-selection-query", with: book.title)
      click_button I18n.t("jjaek_books.finish_selection")
    end
    expect(page).to have_current_path(book_path(book), ignore_query: true)
    expect(page).to have_field("jjaek[content]", with: "Keep this draft while shelving")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all)
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{book.id}']", count: 1)
    expect(user.bookshelf_entries.find_by!(book: book).bookshelf).to eq(shelf)
    expect(user.jjaeks).to be_empty
  end
end
