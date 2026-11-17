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

  it "reports asynchronous move failures and reloads the original membership and registration" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    original = first_entry.attributes
    allow_any_instance_of(BookshelfEntry).to receive(:move_to_bookshelf!) do |record|
      record.errors.add(:base, :invalid)
      raise ActiveRecord::RecordInvalid.new(record)
    end

    %w[validation network].each do |failure|
      visit transfer_user_library_path(user, source_bookshelf_id: first_entry.bookshelf_id, target_bookshelf_id: target_shelf.id)
      expect(page).to have_css("[data-bookshelf-transfer-list-role='source'] [data-bookshelf-entry-id]", count: 2)
      page.execute_script(<<~JS)
        window.bookshelfFailureMarker = true
        if ("#{failure}" === "network") window.fetch = () => Promise.reject(new TypeError("Offline"))
      JS
      message = failure == "validation" ? I18n.t("errors.messages.invalid") : I18n.t("bookshelf_entries.alerts.move_failed")
      accept_alert(message) do
        page.execute_script(<<~JS)
          const element = document.querySelector('[data-controller="bookshelf-transfer"]')
          const target = element.querySelector('[data-bookshelf-transfer-list-role="target"]')
          target.append(element.querySelector('[data-bookshelf-entry-id="#{first_entry.id}"]'))
          window.Stimulus.getControllerForElementAndIdentifier(element, "bookshelf-transfer")
            .move("#{first_entry.id}", "#{target_shelf.id}", null)
        JS
      end
      expect(page).to have_css("[data-bookshelf-transfer-list-role='source'] [data-bookshelf-entry-id]", count: 2)
      expect(page.evaluate_script("typeof window.bookshelfFailureMarker")).to eq("undefined")
      expect(page).to have_no_css("[data-bookshelf-transfer-list-role='target'] [data-bookshelf-entry-id]")
      expect(first_entry.reload.attributes).to eq(original)
      expect(user.bookshelf_entries.count).to eq(2)
      expect(page).to have_no_text(I18n.t("bookshelf_entries.notices.moved", bookshelf_name: target_shelf.name))
    end
  end

  it "reports a transfer-list reorder network failure and reloads the saved order" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    visit transfer_user_library_path(user, source_bookshelf_id: first_entry.bookshelf_id, target_bookshelf_id: target_shelf.id)
    expect(page).to have_css("[data-bookshelf-transfer-list-role='source'] [data-bookshelf-entry-id]", count: 2)
    page.execute_script(<<~JS)
      window.bookshelfFailureMarker = true
      window.fetch = () => Promise.reject(new TypeError("Offline"))
    JS
    accept_alert(I18n.t("bookshelf_entries.alerts.reorder_failed")) do
      page.execute_script(<<~JS)
        const element = document.querySelector('[data-controller="bookshelf-transfer"]')
        const list = element.querySelector('[data-bookshelf-transfer-list-role="source"]')
        Array.from(list.children).reverse().forEach(entry => list.append(entry))
        window.Stimulus.getControllerForElementAndIdentifier(element, "bookshelf-transfer")
          .reorderList(list, "#{first_entry.bookshelf_id}")
      JS
    end
    expect(page).to have_css("[data-bookshelf-transfer-list-role='source'] > [data-bookshelf-entry-id='#{first_entry.id}']:first-child")
    expect(page.evaluate_script("typeof window.bookshelfFailureMarker")).to eq("undefined")
    ids = all("[data-bookshelf-transfer-list-role='source'] > [data-bookshelf-entry-id]").map { |card| card["data-bookshelf-entry-id"].to_i }
    expect(ids).to eq(user.bookshelf_entries.order(:position, :id).pluck(:id))
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
    page.driver.browser.manage.window.resize_to(1280, 900)
    page.execute_script(<<~JS)
      const element = document.querySelector('[data-controller="bookshelf-transfer"]')
      window.Stimulus.getControllerForElementAndIdentifier(element, "bookshelf-transfer")
        .move("#{first_entry.id}", "#{target_shelf.id}", null)
    JS
    expect(page).to have_css("#flash-messages [role='status']", text: I18n.t("bookshelf_entries.notices.moved", bookshelf_name: target_shelf.name))
    expect(page).to have_css("[data-bookshelf-transfer-list-role='target'] [data-bookshelf-entry-id='#{first_entry.id}']")
    expect(first_entry.reload.bookshelf).to eq(target_shelf)
  end
end
