require "rails_helper"

RSpec.describe "Bookshelf card layout", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Layout reader", email: "layout-reader@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "긴 책 제목 " * 20, authors_text: "긴 저자 " * 15, publisher: "긴 출판사 " * 15) }
  let!(:entry) do
    entry = user.bookshelf_entries.create!(book: book)
    entry.user_book.update!(status: :reading)
    entry
  end
  let!(:empty_entry) { user.bookshelf_entries.create!(book: Book.create!(title: "No reading information")) }

  before do
    7.times do |index|
      entry.user_book.sticker_definitions << StickerDefinition.create!(key: "layout_#{index}", name: "Layout sticker #{index}")
    end
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  [ 390, 1280 ].each do |width|
    it "keeps unclipped, equal-height profile cards at #{width}px" do
      driven_by :selenium, using: :headless_chrome, screen_size: [ width, 900 ]
      page.driver.browser.manage.window.resize_to(width, 900)
      visit user_path(user)
      expect(page).to have_css("[data-book-card-information]", count: 2)
      within("[data-bookshelf-entry-id='#{entry.id}']") do
        expect(page).to have_css("[data-reading-sticker-overflow]") do |overflow|
          visible_count = page.all("[data-reading-sticker]").size
          visible_count.between?(0, 6) && overflow.text == "+#{7 - visible_count}" &&
            overflow["title"] == (visible_count...7).map { |index| "Layout sticker #{index}" }.join(", ")
        end
      end
      layout = page.evaluate_script <<~JS
        Array.from(document.querySelectorAll('[data-book-card-information]')).map(info => {
          const card = info.closest('[data-bookshelf-entry-id]').getBoundingClientRect()
          const box = info.getBoundingClientRect()
          const rows = Array.from(info.querySelectorAll('[data-reading-status-row], [data-reading-stickers-row]'))
          const text = [info.querySelector('a'), info.querySelector('p')]
          return {
            cardHeight: card.height,
            informationHeight: box.height,
            fitsCard: box.bottom <= card.bottom && box.right <= card.right,
            singleLineText: text.every(node => getComputedStyle(node).whiteSpace === 'nowrap' && getComputedStyle(node).textOverflow === 'ellipsis'),
            rowsFit: rows.length === 2 && rows.every(row => {
              const bounds = row.getBoundingClientRect()
              return bounds.height > 0 && Array.from(row.children).filter(child => getComputedStyle(child).display !== 'none').every(child => {
                const badge = child.getBoundingClientRect()
                return badge.bottom <= bounds.bottom + 1 && badge.top >= bounds.top - 1 && badge.right <= bounds.right + 1
              })
            })
          }
        })
      JS
      heights = layout.map { |card| card["cardHeight"] }
      expect(heights.max - heights.min).to be < 0.01,
        heights.inspect
      expect(layout.all? { |card| card["fitsCard"] && card["singleLineText"] && card["rowsFit"] }).to be(true)
      information_heights = layout.map { |card| card["informationHeight"] }
      expect(information_heights.max - information_heights.min).to be < 0.01,
        information_heights.inspect
    end
  end

  it "opens an information card from the cover and reaches the existing reading editor through details" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 900 ]
    page.current_window.resize_to(390, 900)
    book.update!(thumbnail: "https://example.test/cover.png")
    library_path = user_library_path(user, bookshelf_id: entry.bookshelf_id)
    visit library_path

    cover = find("[data-bookshelf-entry-id='#{entry.id}'] button[data-bookshelf-cover]")
    details = I18n.t("bookshelf_entries.actions.details")
    expect(page).to have_no_link(details)
    cover.click

    expect(page).to have_current_path(library_path)
    within("dialog[open]") do
      expect(page).to have_css("img[src='#{book.thumbnail}']")
      expect(page).to have_selector("h2", text: book.title.strip)
      expect(page).to have_text(book.authors_text.strip)
      expect(page).to have_css("[data-reading-status='reading']")
      expect(page).to have_css("[data-reading-sticker='layout_0']")
      expect(page).to have_button(I18n.t("bookshelf_entries.actions.remove"))
    end

    page.driver.browser.action.send_keys(:escape).perform
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_css("[data-bookshelf-entry-id='#{entry.id}'] [data-bookshelf-cover]:focus")

    find("[data-bookshelf-entry-id='#{empty_entry.id}'] button[data-bookshelf-cover]").click
    within("dialog[open]") do
      expect(page).to have_text(I18n.t("books.thumbnail.no_thumbnail"))
      click_button I18n.t("bookshelves.actions.close")
    end

    cover.click
    click_link details
    expect(page).to have_current_path(book_path(book, return_to: library_path, tab: "reading"))
    click_button I18n.t("books.show.edit_reading_record")
    expect(page).to have_button(I18n.t("books.show.save_reading_record"))
  end
end
