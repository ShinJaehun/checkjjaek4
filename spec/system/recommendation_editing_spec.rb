require "rails_helper"

RSpec.describe "Unified inline composition", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Reader", email: "inline-composer@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "Search attachment first", thumbnail: "https://example.com/first-cover.jpg") }
  let!(:other_book) { Book.create!(title: "Search attachment second", thumbnail: "https://example.com/second-cover.jpg") }
  let!(:recommendation) do
    record = user.jjaeks.new(content: "Original recommendation", recommendation: true)
    record.jjaek_recommendations.build(book:, position: 0)
    record.save!
    record
  end

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [1280, 720]
    login_as user, scope: :user
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
  end

  after { Warden.test_reset! }

  it "keeps the draft and visibility through page searches, selection, registration and removal" do
    shelf = user.bookshelves.create!(name: "Chosen shelf")
    visit root_path
    fill_in "jjaek[content]", with: "My draft survives"
    choose I18n.t("jjaeks.visibility.private_jjaek"), allow_label_click: true
    click_button I18n.t("jjaek_books.add")
    within("#recommendation-window") do
      expect(page).to have_no_field("jjaek[content]")
      fill_in "recommendation-query", with: "Search attachment"
      click_button I18n.t("book_search.form.submit")
    end
    expect(page).to have_current_path(book_search_path, ignore_query: true)
    within("#recommendation-search-results") do
      expect(page).to have_text(book.title)
      [book, other_book].each do |selected_book|
        within("article[data-book-id='#{selected_book.id}']") do
          click_button I18n.t("jjaek_books.choose")
          expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
        end
      end
    end
    within("#recommendation-window") do
      expect(page).to have_text(book.title)
      click_button I18n.t("recommendations.finish_selection")
    end
    expect(page).to have_current_path(root_path)
    within("#jjaek-attached-books") do
      [book, other_book].each do |selected_book|
        within("[data-book-key='#{selected_book.id}']") do
          expect(page).to have_text(selected_book.title)
          expect(page).to have_css("img[src='#{selected_book.thumbnail}']")
          expect(page).to have_button(I18n.t("jjaek_books.remove"))
          expect(page).to have_button(I18n.t("jjaek_books.add_to_shelf"))
        end
      end
    end
    expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('selected_books[]')")).to eq(["", book.id.to_s, other_book.id.to_s])
    expect(page).to have_field("jjaek[content]", with: "My draft survives")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all)
    within("#jjaek-attached-books [data-book-key='#{book.id}']") { click_button I18n.t("jjaek_books.add_to_shelf") }
    within("dialog[open]") { click_button I18n.t("bookshelves.actions.close") }
    expect(page).to have_field("jjaek[content]", with: "My draft survives")
    within("#jjaek-attached-books [data-book-key='#{book.id}']") { click_button I18n.t("jjaek_books.add_to_shelf") }
    within("dialog[open]") do
      choose shelf.name, allow_label_click: true
      click_button I18n.t("book_search.actions.add_to_shelf")
    end
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_field("jjaek[content]", with: "My draft survives")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all)
    expect(user.bookshelf_entries.find_by!(book:).bookshelf).to eq(shelf)
    within("#jjaek-attached-books [data-book-key='#{book.id}']") do
      click_button I18n.t("jjaek_books.remove")
    end
    expect(page).to have_no_css("#jjaek-attached-books [data-book-key='#{book.id}']")
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{other_book.id}']")
    expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('selected_books[]')")).to eq(["", other_book.id.to_s])
    expect(user.jjaeks.where(content: "My draft survives")).to be_empty
    click_button I18n.t("jjaeks.actions.publish_short")
    expect(page).to have_text("My draft survives")
    saved = user.jjaeks.find_by!(content: "My draft survives")
    expect(saved.attached_books).to eq([other_book])
    expect(saved).to be_private_jjaek
    within("#jjaek_#{saved.id}") do
      expect(page).to have_text(other_book.title)
      expect(page).to have_css("img[src='#{other_book.thumbnail}']")
      expect(page).to have_link(other_book.title)
      expect(page).to have_no_text(book.title)
    end
    expect(user.bookshelf_entries.find_by!(book:).bookshelf).to eq(shelf)
  end

  it "edits a legacy recommendation on the same Rails form and cancels navigation without saving" do
    visit edit_jjaek_path(recommendation)
    expect(page).to have_field("jjaek[content]", with: "Original recommendation")
    expect(page).to have_text(book.title)
    fill_in "jjaek[content]", with: "Discarded draft"
    visit root_path
    expect(recommendation.reload.content).to eq("Original recommendation")
    visit edit_jjaek_path(recommendation)
    within("#jjaek-attached-books") { click_button I18n.t("jjaek_books.remove") }
    fill_in "jjaek[content]", with: "Edited without books"
    click_button I18n.t("jjaeks.actions.save")
    expect(page).to have_text("Edited without books")
    expect(recommendation.reload.attached_books).to be_empty
    expect(recommendation.content).to eq("Edited without books")
  end
end
