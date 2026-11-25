require "rails_helper"

RSpec.describe "Mobile library bookshelf picker", type: :system do
  include Warden::Test::Helpers

  after { Warden.test_reset! }

  it "opens with the keyboard and changes bookshelves without changing the sort" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 700 ]
    page.current_window.resize_to(390, 700)
    reader = User.create!(name: "Picker reader", email: "picker-reader@example.com", password: "password123!")
    shelf = reader.bookshelves.create!(name: "Colorful shelf", color_key: "green")
    reader.bookshelf_entries.create!(bookshelf: shelf, book: Book.create!(title: "Shelved book"))
    login_as reader, scope: :user

    visit user_library_path(reader, sort: "title")

    picker = find("[data-library-mobile-bookshelf-picker]")
    shelf_path = user_library_path(reader, bookshelf_id: shelf.id, sort: "title")
    expect(picker).to have_css("summary", text: "#{reader.default_bookshelf.name} (0)")
    expect(picker).to have_no_link(shelf.name, href: shelf_path)
    picker.find("summary").send_keys(:space)
    expect(picker).to have_link(shelf.name, href: shelf_path)
    expect(picker).to have_css('a[aria-current="page"]', text: reader.default_bookshelf.name)

    page.driver.browser.action.send_keys(:tab, :tab).perform
    expect(picker).to have_css(%(a[href="#{shelf_path}"]:focus))
    page.driver.browser.action.send_keys(:enter).perform

    expect(page).to have_current_path(shelf_path)
    expect(page).to have_css("[data-library-mobile-bookshelf-picker] summary", text: "#{shelf.name} (1)")
    expect(page).to have_no_css("[data-library-mobile-bookshelf-picker][open]")
  end
end
