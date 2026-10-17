require "rails_helper"

RSpec.describe "Bookshelf transfer on mobile", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Transfer reader", email: "transfer-mobile@example.com", password: "password123!") }
  let!(:first_entry) { user.bookshelf_entries.create!(book: Book.create!(title: "First transfer book")) }
  let!(:second_entry) { user.bookshelf_entries.create!(book: Book.create!(title: "Second transfer book")) }
  let!(:target_shelf) { user.bookshelves.create!(name: "Target shelf", visibility: :private) }

  before { login_as user, scope: :user }
  after { Warden.test_reset! }

  it "selects horizontal cards and moves them through the bottom sheet without losing selection on cancel" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 700 ]
    page.driver.browser.manage.window.resize_to(390, 700)
    visit transfer_user_library_path(user, source_bookshelf_id: first_entry.bookshelf_id, target_bookshelf_id: target_shelf.id)

    expect(page).to have_css("[data-bookshelf-transfer-list-role='source'] [data-bookshelf-entry-id]", count: 2)
    expect(page).to have_css("[data-bookshelf-transfer-list-role='target']", visible: false)
    layout = page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector('[data-bookshelf-entry-id="#{first_entry.id}"]')
        const cover = card.querySelector('.w-20').getBoundingClientRect()
        const information = card.querySelector('[data-book-card-information]').getBoundingClientRect()
        return {
          viewport: window.innerWidth,
          desktopBreakpoint: window.matchMedia("(min-width: 768px)").matches,
          cardHeight: card.getBoundingClientRect().height,
          coverRight: cover.right,
          informationLeft: information.left,
          flexDirection: getComputedStyle(card.querySelector(".flex.h-full")).flexDirection
        }
      })()
    JS
    expect(layout["cardHeight"]).to be_within(0.01).of(144)
    expect(layout["coverRight"]).to be <= layout["informationLeft"]
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    expect(page).to have_button(I18n.t("bookshelf_entries.actions.move"), disabled: true)
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionModeButton']")

    first_card = find("[data-bookshelf-entry-id='#{first_entry.id}']")
    expect(first_card).to have_css("input[type='checkbox']", visible: true)
    expect(first_card).to have_link("First transfer book")
    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const card = document.querySelector('[data-bookshelf-entry-id="#{first_entry.id}"]')
        const information = card.querySelector('[data-book-card-information]').getBoundingClientRect()
        const checkbox = card.querySelector('[data-bookshelf-transfer-target=selectionCheckboxWrapper]').getBoundingClientRect()
        return information.right > checkbox.left
      })()
    JS
    first_card.click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("1")
    expect(page).to have_button(I18n.t("bookshelf_entries.actions.move"), disabled: false)
    expect(first_card[:class]).to include("border-stone-900")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('[data-bookshelf-transfer-target=selectionCheckboxWrapper]')).position")).to eq("absolute")
    first_card.find("input[type='checkbox']").click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    first_card.find("input[type='checkbox']").click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("1")
    first_card.click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    first_card.click
    find("[data-bookshelf-entry-id='#{second_entry.id}']").click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")
    click_button I18n.t("users.library.transfer.clear_selection")
    expect(first_card).to have_css("input[type='checkbox']", visible: true)
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    expect(page).to have_button(I18n.t("bookshelf_entries.actions.move"), disabled: true)

    first_card.click
    find("[data-bookshelf-entry-id='#{second_entry.id}']").click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")
    click_button I18n.t("bookshelf_entries.actions.move")
    expect(page).to have_css("[role='dialog'][aria-modal='true']", visible: true)
    expect(find("[data-bookshelf-transfer-target='sheetSelectedCount']")).to have_text("2")
    expect(page).to have_button("Target shelf")
    expect(page).to have_no_button(first_entry.bookshelf.name)

    click_button I18n.t("users.library.transfer.cancel_move")
    expect(page).to have_no_css("[role='dialog']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")
    expect(page.evaluate_script("document.activeElement === document.querySelector('[data-bookshelf-transfer-target=moveButton]')")).to be(true)

    click_button I18n.t("bookshelf_entries.actions.move")
    page.driver.browser.action.send_keys(:escape).perform
    expect(page).to have_no_css("[role='dialog']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")

    click_button I18n.t("bookshelf_entries.actions.move")
    page.execute_script("document.querySelector('[data-bookshelf-transfer-target=movePanel]').click()")
    expect(page).to have_no_css("[role='dialog']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")

    click_button I18n.t("bookshelf_entries.actions.move")
    click_button "Target shelf"
    expect(page).to have_select("source_bookshelf_id", selected: "Target shelf (2)")
    expect(first_entry.reload.bookshelf).to eq(target_shelf)
    expect(second_entry.reload.bookshelf).to eq(target_shelf)
  end

  it "keeps two compact panels and drag handles on desktop" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    page.driver.browser.manage.window.resize_to(1280, 900)
    visit transfer_user_library_path(user, source_bookshelf_id: first_entry.bookshelf_id, target_bookshelf_id: target_shelf.id)

    expect(page).to have_css("[data-bookshelf-transfer-target='list']", count: 2, visible: true)
    expect(page).to have_css("[data-bookshelf-entry-view='compact']", count: 2)
    expect(page).to have_css("[data-bookshelf-entry-id][data-bookshelf-entries-sort-handle]", count: 2)
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionCheckboxWrapper']", visible: true)

    page.driver.browser.manage.window.resize_to(390, 700)
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    find("[data-bookshelf-entry-id='#{first_entry.id}']").click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("1")

    page.driver.browser.manage.window.resize_to(1280, 900)
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(page).to have_css("[data-bookshelf-transfer-target='list']", count: 2, visible: true)
    expect(page).to have_css("input[name='transfer_selection_#{first_entry.id}']:not(:checked)", visible: :all)

    page.driver.browser.manage.window.resize_to(390, 700)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    expect(page).to have_button(I18n.t("bookshelf_entries.actions.move"), disabled: true)
  end
end
