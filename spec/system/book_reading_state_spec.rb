require "rails_helper"

RSpec.describe "Book reading state", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Reader", email: "reading-system@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "독서 기록 책", authors_text: "저자") }
  let!(:entry) { user.bookshelf_entries.create!(book:, status: :reading) }
  let!(:first_sticker) { StickerDefinition.create!(key: "reading_first", name: "추천") }
  let!(:second_sticker) { StickerDefinition.create!(key: "reading_second", name: "감동") }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    login_as user, scope: :user
    visit book_path(book)
  end

  after { Warden.test_reset! }

  it "keeps selections local until one save records status and stickers together" do
    find("button[aria-controls='book-reading-dialog']").click
    expect(page).to have_css("dialog#book-reading-dialog[open]")

    choose I18n.t("bookshelf_entries.statuses.finished"), allow_label_click: true
    check first_sticker.name, allow_label_click: true
    check second_sticker.name, allow_label_click: true

    expect(entry.reload.status).to eq("reading")
    expect(entry.sticker_definition_ids).to be_empty
    expect(entry.book_activities).to be_empty

    click_button I18n.t("books.show.save_reading_record")

    expect(page).to have_text(I18n.t("bookshelf_entries.statuses.finished"))
    expect(page).to have_text(first_sticker.name)
    expect(page).to have_text(second_sticker.name)
    expect(entry.reload.status).to eq("finished")
    expect(entry.sticker_definition_ids).to match_array([ first_sticker.id, second_sticker.id ])
    expect(entry.book_activities.reload.pluck(:action)).to eq([ "bookshelf_entry_updated" ])
  end

  it "clears status and all stickers with one save" do
    entry.sticker_definitions << first_sticker
    visit book_path(book)
    find("button[aria-controls='book-reading-dialog']").click
    expect(page).to have_css("dialog#book-reading-dialog[open]")
    choose I18n.t("books.show.clear_status"), allow_label_click: true
    uncheck first_sticker.name, allow_label_click: true

    expect(page).to have_checked_field(I18n.t("books.show.clear_status"))
    expect(page).to have_unchecked_field(first_sticker.name)

    click_button I18n.t("books.show.save_reading_record")

    expect(page).to have_text(I18n.t("bookshelf_entries.notices.updated"))

    expect(entry.reload.status).to be_nil
    expect(entry.sticker_definition_ids).to be_empty
    expect(entry.book_activities.reload.count).to eq(1)
  end

  it "preserves submitted sticker selections without persisting an invalid status" do
    find("button[aria-controls='book-reading-dialog']").click
    expect(page).to have_css("dialog#book-reading-dialog[open]")
    choose I18n.t("bookshelf_entries.statuses.finished"), allow_label_click: true
    check first_sticker.name, allow_label_click: true
    page.execute_script("document.querySelector('input[name=\"bookshelf_entry[status]\"]:checked').value = 'invalid'")
    click_button I18n.t("books.show.save_reading_record")

    expect(page).to have_css("dialog#book-reading-dialog[open] form[action='#{bookshelf_entry_path(entry)}']")
    expect(page).to have_checked_field(first_sticker.name, visible: :all)
    expect(entry.reload.status).to eq("reading")
    expect(entry.sticker_definition_ids).to be_empty
    expect(entry.book_activities.reload).to be_empty
  end

  it "shows the book writing form inline alongside the reading modal" do
    expect(page).to have_css("#book-jjaek-form form[action='#{jjaeks_path}']")
    expect(page).to have_no_css("#book-writing-dialog")
    expect(page).to have_css("dialog#book-reading-dialog:not([open])", visible: :all)
    expect(page).to have_field("jjaek[content]")
  end
end
