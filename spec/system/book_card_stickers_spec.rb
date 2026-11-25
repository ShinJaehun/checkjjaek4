require "rails_helper"

RSpec.describe "Responsive book card stickers", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Sticker reader", email: "responsive-stickers@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Responsive sticker book", authors_text: "Author", publisher: "Publisher") }
  let!(:entry) do
    entry = user.bookshelf_entries.create!(book:)
    entry.user_book.update!(status: :reading)
    entry
  end
  let!(:stickers) do
    7.times.map do |index|
      StickerDefinition.create!(key: "responsive_sticker_#{index}", name: "Sticker #{index}")
    end
  end

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    entry.user_book.sticker_definitions = stickers
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  %i[profile library].each do |location|
    it "fits icons and exact overflow names without changing the #{location} layout at a fixed viewport width" do
      visit(location == :profile ? user_path(user) : user_library_path(user))
      card = find("[data-bookshelf-entry-id='#{entry.id}']")
      layout = location == :library ? find(".bookshelf-shelf") : card
      measure_height = "this.getBoundingClientRect().height"
      desktop_height = layout.evaluate_script(measure_height)
      card.find("button[data-bookshelf-cover]").click if location == :library
      row = card.find("[data-reading-stickers-row]")
      information = card.find("[data-book-card-information]")
      height_script = <<~JS
        Array.from(this.querySelectorAll(
          ':scope > a, :scope > h2, :scope > p, [data-reading-status-row], [data-reading-stickers-row]'
        )).map(element => element.getBoundingClientRect().height)
      JS
      row_heights = information.evaluate_script(height_script)

      expect(row).to have_css("[data-reading-sticker]", count: 6)
      expect(row).to have_css("[data-reading-sticker-overflow][title='Sticker 6']", text: "+1")
      expect(layout.evaluate_script(measure_height)).to eq(desktop_height)

      # Resize the measured area without navigating, so ResizeObserver must recalculate.
      page.execute_script("arguments[0].style.width = '76px'", row)
      expect(row).to have_css("[data-reading-sticker]", count: 2)
      summary = row.find("[data-reading-sticker-overflow]", text: "+5")
      expect(summary["title"]).to eq(stickers.drop(2).map(&:name).join(", "))
      expect(summary["aria-label"]).to eq("#{I18n.t('bookshelf_entries.stickers.summary', count: 5)}: #{stickers.drop(2).map(&:name).join(', ')}")
      expect(summary["tabindex"]).to eq("0")
      expect(layout.evaluate_script(measure_height)).to eq(desktop_height)
      expect(information.evaluate_script(height_script)).to eq(row_heights)

      page.execute_script("arguments[0].style.removeProperty('width')", row)
      expect(row).to have_css("[data-reading-sticker]", count: 6)
      expect(row).to have_css("[data-reading-sticker-overflow][title='Sticker 6']", text: "+1")

      page.current_window.resize_to(390, 844)
      expect(row).to have_css("[data-reading-sticker-overflow]") do |overflow|
        visible_count = row.all("[data-reading-sticker]").size
        remaining = stickers.size - visible_count
        visible_count <= 6 && overflow.text == "+#{remaining}" &&
          overflow["title"] == stickers.drop(visible_count).map(&:name).join(", ") &&
          overflow.evaluate_script("this.getBoundingClientRect().right <= this.parentElement.getBoundingClientRect().right + 0.5")
      end
      expect(row.evaluate_script("this.scrollWidth <= this.clientWidth")).to be(true)

      if location == :library
        open_shelf_height = layout.evaluate_script(measure_height)
        card.find("dialog[open]").click_button I18n.t("bookshelves.actions.close")
        expect(card).to have_no_css("dialog[open]")
        expect(layout.evaluate_script(measure_height)).to eq(open_shelf_height)
      else
        expect(layout.evaluate_script(measure_height)).to eq(desktop_height)
      end
    end
  end

  it "shows all six icons without a summary when they fit and adds the summary only when needed" do
    entry.user_book.sticker_definitions.delete(stickers.last)
    visit user_library_path(user)
    find("[data-bookshelf-entry-id='#{entry.id}'] button[data-bookshelf-cover]").click
    row = find("[data-bookshelf-entry-id='#{entry.id}'] [data-reading-stickers-row]")

    expect(row).to have_css("[data-reading-sticker]", count: 6)
    expect(row).to have_no_css("[data-reading-sticker-overflow]")

    page.execute_script("arguments[0].style.width = '76px'", row)
    expect(row).to have_css("[data-reading-sticker]", count: 2)
    expect(row).to have_css("[data-reading-sticker-overflow]", text: "+4")

    page.execute_script("arguments[0].style.removeProperty('width')", row)
    expect(row).to have_css("[data-reading-sticker]", count: 6)
    expect(row).to have_no_css("[data-reading-sticker-overflow]")
  end

  it "measures stickers when a previously hidden profile carousel page becomes visible" do
    entry.update!(created_at: 2.days.ago, updated_at: 2.days.ago)
    4.times do |index|
      user.bookshelf_entries.create!(book: Book.create!(title: "Newer book #{index}", authors_text: "Author"))
    end
    visit user_path(user)

    expect(page).to have_no_css("[data-bookshelf-entry-id='#{entry.id}']")
    find("button[data-action='click->profile-books-carousel#next']").click

    row = find("[data-bookshelf-entry-id='#{entry.id}'] [data-reading-stickers-row]")
    expect(row).to have_css("[data-reading-sticker]", count: 6)
    expect(row).to have_css("[data-reading-sticker-overflow][title='Sticker 6']", text: "+1")
  end
end
