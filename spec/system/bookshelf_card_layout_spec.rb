require "rails_helper"

RSpec.describe "Bookshelf card layout", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Layout reader", email: "layout-reader@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "긴 책 제목 " * 20, authors_text: "긴 저자 " * 15, publisher: "긴 출판사 " * 15) }
  let!(:entry) { user.bookshelf_entries.create!(book: book, status: :reading) }
  let!(:empty_entry) { user.bookshelf_entries.create!(book: Book.create!(title: "No reading information")) }
  let!(:target_shelf) { user.bookshelves.create!(name: "Target", visibility: :private) }

  before do
    7.times do |index|
      entry.sticker_definitions << StickerDefinition.create!(key: "layout_#{index}", name: "Layout sticker #{index}")
    end
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  [ 390, 1280 ].each do |width|
    it "keeps two reading rows and unclipped, equal-height information at #{width}px" do
      driven_by :selenium, using: :headless_chrome, screen_size: [ width, 900 ]
      paths = [
        user_path(user),
        user_library_path(user),
        transfer_user_library_path(user, source_bookshelf_id: entry.bookshelf_id, target_bookshelf_id: target_shelf.id)
      ]
      paths.each do |path|
        visit path
        expect(page).to have_css("[data-book-card-information]", count: 2)
        within("[data-bookshelf-entry-id='#{entry.id}']") do
          expect(page).to have_css("[data-reading-sticker]", count: 3)
          expect(page).to have_css("[data-reading-sticker-overflow]", text: "+4")
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
                return bounds.height > 0 && Array.from(row.children).every(child => {
                  const badge = child.getBoundingClientRect()
                  return badge.bottom <= bounds.bottom + 1 && badge.top >= bounds.top - 1 && badge.right <= bounds.right + 1
                })
              })
            }
          })
        JS
        expect(layout.map { |card| card["cardHeight"] }.uniq.size).to eq(1)
        expect(layout.all? { |card| card["fitsCard"] && card["singleLineText"] && card["rowsFit"] }).to be(true)
        expect(layout.map { |card| card["informationHeight"] }.uniq.size).to eq(1)
      end
    end
  end
end
