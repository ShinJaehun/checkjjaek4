require "rails_helper"

RSpec.describe "Bookshelf transfer", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Transfer reader", email: "transfer-mobile@example.com", password: "password123!") }
  let!(:first_entry) { user.bookshelf_entries.create!(book: Book.create!(title: "First transfer book")) }
  let!(:second_entry) { user.bookshelf_entries.create!(book: Book.create!(title: "Second transfer book")) }
  let!(:target_shelf) { user.bookshelves.create!(name: "Target shelf", visibility: :private) }

  before { login_as user, scope: :user }
  after { Warden.test_reset! }

  def find_connected_transfer(sortable_count: nil)
    find("[data-controller~='bookshelf-transfer']") do |element|
      page.evaluate_script(<<~JS, element, sortable_count)
        (() => {
          const controller = window.Stimulus?.getControllerForElementAndIdentifier(arguments[0], "bookshelf-transfer")
          return !!controller && (arguments[1] === null || controller.sortables.length === arguments[1])
        })()
      JS
    end
  end

  def click_cover(entry)
    find("[data-bookshelf-entry-id='#{entry.id}'] button[data-bookshelf-cover]") do |cover|
      page.evaluate_script(<<~JS, cover)
        !!window.Stimulus?.getControllerForElementAndIdentifier(arguments[0].closest("[data-controller~='book-modal']"), "book-modal")
      JS
    end.click
  end

  it "opens the source shelf in the organizer from the old mobile URL and preserves selection on cancel" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 700 ]
    page.driver.browser.manage.window.resize_to(390, 700)
    source_shelf = first_entry.bookshelf
    user.bookshelf_entries.create!(book: Book.create!(title: "Book already on the target shelf"), bookshelf: target_shelf)
    target_label = "#{target_shelf.name} #{I18n.t("reading_experience.book_count", count: 1)}"
    visit transfer_user_library_path(user, source_bookshelf_id: source_shelf.id, target_bookshelf_id: target_shelf.id)

    expect(page).to have_current_path(transfer_user_library_path(user, mode: "organize", source_bookshelf_id: source_shelf.id))
    expect(page).to have_selector("h1", text: I18n.t("users.library.transfer.organize"), exact_text: true)
    expect(page).to have_css("[data-bookshelf-transfer-list-role='source'] [data-bookshelf-entry-id]", count: 2)
    expect(page).to have_no_css("[data-bookshelf-transfer-list-role='target']", visible: :all)
    first_card = find("[data-bookshelf-entry-id='#{first_entry.id}']")
    second_card = find("[data-bookshelf-entry-id='#{second_entry.id}']")
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    manage_label = I18n.t("users.library.transfer.manage_selection")
    expect(page).to have_button(manage_label, disabled: true)
    first_checkbox = first_card.find("input[type='checkbox']")
    second_checkbox = second_card.find("input[type='checkbox']")

    click_cover(first_entry)
    expect(first_card).to have_no_css("dialog[open]")
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("1")
    expect(page).to have_button(manage_label, disabled: false)
    expect(first_card[:class].split).to include("ring-2")
    first_checkbox.click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    first_checkbox.click
    second_checkbox.click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")
    click_button I18n.t("users.library.transfer.clear_selection")
    expect(first_card).to have_css("input[type='checkbox']", visible: true)
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    expect(page).to have_button(manage_label, disabled: true)

    first_checkbox.click
    second_checkbox.click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")
    click_button manage_label
    expect(page).to have_css("[role='dialog'][aria-modal='true']", visible: true)
    expect(find("[data-bookshelf-transfer-target='sheetSelectedCount']")).to have_text("2")
    expect(page).to have_button(target_label, exact: true)
    expect(page).to have_no_button(first_entry.bookshelf.name)
    expect(page).to have_button(I18n.t("bookshelf_entries.actions.remove"))

    click_button I18n.t("users.library.transfer.cancel_move")
    expect(page).to have_no_css("[role='dialog']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")
    expect(page.evaluate_script("document.activeElement === document.querySelector('[data-bookshelf-transfer-target=moveButton]')")).to be(true)

    click_button manage_label
    page.driver.browser.action.send_keys(:escape).perform
    expect(page).to have_no_css("[role='dialog']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")

    click_button manage_label
    page.execute_script("document.querySelector('[data-bookshelf-transfer-target=movePanel]').click()")
    expect(page).to have_no_css("[role='dialog']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")

    click_button manage_label
    click_button target_label, exact: true
    expect(page).to have_css("[data-library-mobile-bookshelf-picker] summary", text: "#{source_shelf.name} (0)")
    expect(first_entry.reload.bookshelf).to eq(target_shelf)
    expect(second_entry.reload.bookshelf).to eq(target_shelf)
  end

  it "moves and removes selected books from the mobile organizer with confirmation" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 700 ]
    page.driver.browser.manage.window.resize_to(390, 700)
    source_shelf = first_entry.bookshelf
    target_shelf.update!(color_key: "green")
    visit user_library_path(user, bookshelf_id: source_shelf.id)
    within("[data-library-bookshelf-management]") do
      find("summary").send_keys(:space)
      expect(page).to have_no_link(I18n.t("users.library.transfer.title"), exact: true)
      click_link I18n.t("users.library.transfer.organize")
    end
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)

    manage_label = I18n.t("users.library.transfer.manage_selection")
    remove_label = I18n.t("bookshelf_entries.actions.remove")
    preservation = I18n.t("bookshelf_entries.confirmations.reading_record_preserved")
    expect(page).to have_no_button(remove_label)
    find("input[name='transfer_selection_#{first_entry.id}']").click
    click_button manage_label
    dismiss_confirm([ I18n.t("bookshelf_entries.confirmations.remove"), preservation ].join("\n\n")) do
      click_button remove_label
    end
    expect(find("[data-bookshelf-transfer-target='sheetSelectedCount']")).to have_text("1")
    expect(first_entry.reload).to be_persisted

    click_button I18n.t("users.library.transfer.cancel_move")
    find("input[name='transfer_selection_#{second_entry.id}']").click
    click_button manage_label
    click_button target_shelf.name
    expect(page).to have_css("#flash-messages [role='status']", text: I18n.t("bookshelf_entries.notices.bulk_moved", count: 2, bookshelf_name: target_shelf.name))
    picker = "[data-library-mobile-bookshelf-picker]"
    expect(page).to have_css("#{picker} summary", text: "#{source_shelf.name} (0)")
    expect(first_entry.reload.bookshelf).to eq(target_shelf)
    expect(second_entry.reload.bookshelf).to eq(target_shelf)

    target_path = transfer_user_library_path(user, mode: "organize", source_bookshelf_id: target_shelf.id)
    source_path = transfer_user_library_path(user, mode: "organize", source_bookshelf_id: source_shelf.id)
    within(picker) do
      find("summary").send_keys(:space)
      expect(page).to have_css("a.bg-green-50", text: "#{target_shelf.name} (2)")
      click_link "#{target_shelf.name} (2)", href: target_path
    end
    expect(page).to have_current_path(target_path)
    expect(page).to have_css("#{picker} summary.bg-green-50", text: "#{target_shelf.name} (2)")
    expect(page).to have_css("[data-bookshelf-transfer-target='list'][data-bookshelf-transfer-bookshelf-id='#{target_shelf.id}']")
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")

    find("input[name='transfer_selection_#{first_entry.id}']").click
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("1")
    within(picker) do
      find("summary").click
      expect(page).to have_css("a.bg-green-600[aria-current='page']", text: "#{target_shelf.name} (2)")
      click_link "#{source_shelf.name} (0)", href: source_path
    end
    expect(page).to have_current_path(source_path)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")

    within(picker) do
      find("summary").click
      click_link "#{target_shelf.name} (2)", href: target_path
    end
    expect(page).to have_current_path(target_path)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")

    find("input[name='transfer_selection_#{first_entry.id}']").click
    find("input[name='transfer_selection_#{second_entry.id}']").click
    click_button manage_label
    accept_confirm([ I18n.t("bookshelf_entries.confirmations.remove_selected", books_count: 2), preservation ].join("\n\n")) do
      click_button remove_label
    end

    expect(page).to have_no_css("[data-bookshelf-transfer-list-role='source'] [data-bookshelf-entry-id]")
    expect(page).to have_no_css("[role='dialog']", visible: true)
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    expect(page).to have_button(manage_label, disabled: true)
    expect(user.user_books.count).to eq(2)
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
      transfer = find_connected_transfer
      page.execute_script(<<~JS)
        window.bookshelfFailureMarker = true
        if ("#{failure}" === "network") window.fetch = () => Promise.reject(new TypeError("Offline"))
      JS
      message = failure == "validation" ? I18n.t("errors.messages.invalid") : I18n.t("bookshelf_entries.alerts.move_failed")
      accept_alert(message) do
        page.execute_script(<<~JS, transfer)
          const element = arguments[0]
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
    transfer = find_connected_transfer
    page.execute_script(<<~JS)
      window.bookshelfFailureMarker = true
      window.fetch = () => Promise.reject(new TypeError("Offline"))
    JS
    accept_alert(I18n.t("bookshelf_entries.alerts.reorder_failed")) do
      page.execute_script(<<~JS, transfer)
        const element = arguments[0]
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

  it "keeps the original order on cancel and removes only the confirmed placement from the information card" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    path = transfer_user_library_path(user, source_bookshelf_id: first_entry.bookshelf_id, target_bookshelf_id: target_shelf.id)
    first_entry.user_book.update!(status: :reading)
    visit path
    find_connected_transfer

    confirmation = [ I18n.t("bookshelf_entries.confirmations.remove"),
      I18n.t("bookshelf_entries.confirmations.reading_record_preserved") ].join("\n\n")
    click_cover(first_entry)
    dismiss_confirm(confirmation) { click_button I18n.t("bookshelf_entries.actions.remove") }

    source_cards = "[data-bookshelf-transfer-list-role='source'] > [data-bookshelf-entry-id]"
    expect(all(source_cards).map { |card| card["data-bookshelf-entry-id"] }).to eq([ first_entry.id.to_s, second_entry.id.to_s ])
    expect(first_entry.reload.position).to be < second_entry.reload.position
    expect(page).to have_css("dialog[open]")

    accept_confirm(confirmation) { click_button I18n.t("bookshelf_entries.actions.remove") }

    expect(page).to have_css("#flash-messages [role='status']", text: I18n.t("bookshelf_entries.notices.destroyed"))
    expect(page).to have_current_path(path)
    expect(page).to have_no_css("[data-bookshelf-entry-id='#{first_entry.id}']")
    expect(page).to have_css("#{source_cards}[data-bookshelf-entry-id='#{second_entry.id}']")
    expect(first_entry.user_book.reload.status).to eq("reading")
  end

  it "alerts and reloads the saved target shelf when a confirmed removal request fails" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    entry = user.bookshelf_entries.create!(book: Book.create!(title: "Target book"), bookshelf: target_shelf)
    visit transfer_user_library_path(user, source_bookshelf_id: first_entry.bookshelf_id, target_bookshelf_id: target_shelf.id)
    find_connected_transfer
    click_cover(entry)
    find("dialog[open] form[data-controller='bookshelf-form-recovery']") do |form|
      page.evaluate_script(<<~JS, form)
        !!window.Stimulus?.getControllerForElementAndIdentifier(arguments[0], "bookshelf-form-recovery")
      JS
    end
    page.execute_script(<<~JS, bookshelf_entry_path(entry))
      window.bookshelfRemovalFailure = true
      const removalPath = arguments[0]
      const originalFetch = window.fetch
      window.fetch = (url, options) => {
        if (new URL(url, location.href).pathname === removalPath && options?.method?.toUpperCase() === "POST") {
          return Promise.reject(new TypeError("Offline"))
        }
        return originalFetch(url, options)
      }
    JS

    accept_alert(I18n.t("bookshelf_entries.alerts.remove_failed")) do
      accept_confirm(I18n.t("bookshelf_entries.confirmations.remove")) do
        click_button I18n.t("bookshelf_entries.actions.remove")
      end
    end

    find("[data-bookshelf-transfer-list-role='target'] > [data-bookshelf-entry-id='#{entry.id}']") do
      page.evaluate_script("typeof window.bookshelfRemovalFailure === 'undefined'")
    end
    expect(entry.reload.bookshelf).to eq(target_shelf)
  end

  it "organizes one shelf at a time on desktop and returns to the normal library on exit" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    source_shelf = first_entry.bookshelf
    target_entry = user.bookshelf_entries.create!(book: Book.create!(title: "Target book"), bookshelf: target_shelf)
    visit user_library_path(user, bookshelf_id: source_shelf.id)
    within("[data-library-bookshelf-management]") do
      find("summary").click
      click_link I18n.t("users.library.transfer.organize")
    end
    find_connected_transfer(sortable_count: 0)
    expect(page).to have_css("[data-bookshelf-transfer-target='list']", count: 1)
    manage_label = I18n.t("users.library.transfer.manage_selection")

    click_cover(first_entry)
    expect(page).to have_no_css("dialog[open]")
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("1")
    expect(page).to have_no_css("[data-bookshelf-entries-sort-handle]")
    click_link target_shelf.name
    expect(page).to have_css("[data-bookshelf-transfer-target='list'][data-bookshelf-transfer-bookshelf-id='#{target_shelf.id}']")
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")

    click_link source_shelf.name
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    click_cover(first_entry)
    click_cover(second_entry)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("2")
    click_button manage_label
    expect(page).to have_no_button(source_shelf.name)
    click_button target_shelf.name
    expect(page).to have_css("#flash-messages [role='status']", text: I18n.t("bookshelf_entries.notices.bulk_moved", count: 2, bookshelf_name: target_shelf.name))
    expect(first_entry.reload.bookshelf).to eq(target_shelf)
    expect(second_entry.reload.bookshelf).to eq(target_shelf)

    click_link target_shelf.name
    expect(page).to have_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(find("[data-bookshelf-transfer-target='selectedCount']")).to have_text("0")
    click_cover(first_entry)
    click_cover(second_entry)
    click_button manage_label
    accept_confirm(I18n.t("bookshelf_entries.confirmations.remove_selected", books_count: 2)) do
      click_button I18n.t("bookshelf_entries.actions.remove")
    end

    expect(page).to have_no_css("[data-bookshelf-entry-id='#{first_entry.id}'], [data-bookshelf-entry-id='#{second_entry.id}']")
    expect(page).to have_css("[data-bookshelf-entry-id='#{target_entry.id}']")
    expect(target_shelf.bookshelf_entries.order(:position).pluck(:id)).to eq([ target_entry.id ])
    expect(user.user_books.count).to eq(3)

    click_link I18n.t("users.library.transfer.exit_selection_mode")
    expect(page).to have_current_path(user_library_path(user, bookshelf_id: target_shelf.id))
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionBar']")
    click_cover(target_entry)
    expect(page).to have_css("dialog[open]", text: target_entry.book.title)
    click_button I18n.t("bookshelves.actions.close")
    within("[data-library-bookshelf-management]") do
      find("summary").click
      click_link I18n.t("users.library.transfer.title")
    end
    find_connected_transfer(sortable_count: 2)
  end

  it "keeps two shelf lists and drag handles on desktop" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    page.driver.browser.manage.window.resize_to(1280, 900)
    visit transfer_user_library_path(user, source_bookshelf_id: first_entry.bookshelf_id, target_bookshelf_id: target_shelf.id)

    expect(page).to have_selector("h1", text: I18n.t("users.library.transfer.title"), exact_text: true)
    expect(page).to have_css("[data-bookshelf-transfer-target='list']", count: 2, visible: true)
    expect(page).to have_css("[data-bookshelf-transfer-target='list'] > [data-bookshelf-entry-id] button[data-bookshelf-cover]", count: 2)
    expect(page).to have_css("[data-bookshelf-entry-id][data-bookshelf-entries-sort-handle]", count: 2)
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionCheckboxWrapper']", visible: true)

    page.driver.browser.manage.window.resize_to(390, 700)
    expect(page).to have_link(I18n.t("users.library.transfer.organize"),
                              href: transfer_user_library_path(user, mode: "organize", source_bookshelf_id: first_entry.bookshelf_id))
    expect(page).to have_no_css("[data-bookshelf-transfer-target='list']", visible: true)
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)

    page.driver.browser.manage.window.resize_to(1280, 900)
    expect(page).to have_no_css("[data-bookshelf-transfer-target='selectionBar']", visible: true)
    expect(page).to have_css("[data-bookshelf-transfer-target='list']", count: 2, visible: true)
    expect(page).to have_no_link(I18n.t("users.library.transfer.organize"), exact: true)
    find_connected_transfer(sortable_count: 2)
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
