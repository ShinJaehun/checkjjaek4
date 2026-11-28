require "rails_helper"

RSpec.describe "Mobile bookshelf ordering", type: :system do
  include Warden::Test::Helpers

  let(:owner) { User.create!(name: "Order owner", email: "order-owner@example.com", password: "password123!") }
  let!(:first_entry) { owner.bookshelf_entries.create!(book: Book.create!(title: "First order book")) }
  let!(:second_entry) { owner.bookshelf_entries.create!(book: Book.create!(title: "Second order book")) }
  let!(:third_entry) { owner.bookshelf_entries.create!(book: Book.create!(title: "Third order book")) }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 700 ]
    page.current_window.resize_to(390, 700)
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
    login_as owner, scope: :user
  end

  after { Warden.test_reset! }

  def shelf_list
    find("[data-bookshelf-entries-sort-target='list']") do |list|
      page.evaluate_script(<<~JS, list)
        !!window.Stimulus?.getControllerForElementAndIdentifier(
          arguments[0].closest("[data-controller~='bookshelf-entries-sort']"), "bookshelf-entries-sort"
        )?.sortable
      JS
    end
  end

  def visible_entry_ids
    all("[data-bookshelf-entries-sort-target='list'] > [data-bookshelf-entry-id]").map { |card| card["data-bookshelf-entry-id"].to_i }
  end

  def saved_entry_ids
    owner.bookshelf_entries.order(:position, :id).pluck(:id)
  end

  def cover_for(entry)
    shelf_list.find("[data-bookshelf-entry-id='#{entry.id}'] [data-bookshelf-cover]")
  end

  def cover_center(cover)
    page.evaluate_script(<<~JS, cover)
      (() => {
        const rect = arguments[0].getBoundingClientRect()
        return [rect.left + rect.width / 2, rect.top + rect.height / 2].map(Math.round)
      })()
    JS
  end

  def touch(from, to: nil, hold: 0)
    actions = page.driver.browser.action
    finger = actions.add_pointer_input(:touch, "reorder-finger")
    actions.move_to_location(*from, device: finger.name, duration: 0)
           .pointer_down(device: finger.name)
    actions.pause(device: finger, duration: hold)
    actions.move_to_location(*to, device: finger.name, duration: 0) if to
    actions.pointer_up(device: finger.name).perform
  end

  def with_active_touch(from)
    # ChromeDriver only dispatches W3C touch moves and releases in the same perform call as pointer down.
    dispatch_touch("touchStart", from)
    yield
  ensure
    dispatch_touch("touchEnd")
  end

  def dispatch_touch(type, point = nil)
    touch_points = point ? [ { x: point.first, y: point.last } ] : []
    page.driver.browser.execute_cdp("Input.dispatchTouchEvent", type:, touchPoints: touch_points)
  end

  def choose_book(entry)
    cover_for(entry).send_keys([ :shift, :enter ])
    expect(page).to have_css("[data-bookshelf-entry-id='#{entry.id}'][data-reorder-selected]")
  end

  it "allows accessible moves below the covers and saves them immediately" do
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    visit user_library_path(owner, sort: "manual")
    shelf_list
    expect(visible_entry_ids).to eq([ first_entry.id, second_entry.id, third_entry.id ])
    expect(page).to have_no_css("article [data-bookshelf-entries-sort-target='controls']", visible: :all)
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']")
    expect(page).to have_no_css("#library-bookshelf-order-book", visible: :all)

    choose_book(first_entry)
    move_up = I18n.t("users.profile.bookshelf_sort.move_up", title: first_entry.book.title)
    move_down = I18n.t("users.profile.bookshelf_sort.move_down", title: first_entry.book.title)
    expect(page).to have_button(move_up, disabled: true, enable_aria_label: true)
    expect(page).to have_css("[data-bookshelf-entries-sort-target='downButton']:focus")
    find_button(move_down, enable_aria_label: true).send_keys(:enter)
    expect(page).to have_button(move_down, disabled: false, enable_aria_label: true)
    expect(page).to have_css("[data-bookshelf-entries-sort-target='downButton']:focus")
    expect(saved_entry_ids).to eq([ second_entry.id, first_entry.id, third_entry.id ])
    expect(page).to have_css("[data-bookshelf-entries-sort-target='selectedStatus']", text: "#{first_entry.book.title} (2/3)")

    choose_book(third_entry)
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.move_down", title: third_entry.book.title), disabled: true, enable_aria_label: true)
    find_button(I18n.t("users.profile.bookshelf_sort.move_up", title: third_entry.book.title), enable_aria_label: true).send_keys(:escape)
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']")
    expect(page).to have_css("[data-bookshelf-entry-id='#{third_entry.id}'] [data-bookshelf-cover]:focus")
    page.refresh
    expect(visible_entry_ids).to eq([ second_entry.id, first_entry.id, third_entry.id ])
  end

  it "keeps mouse input out of touch mode after narrowing the desktop browser" do
    page.current_window.resize_to(1280, 900)
    path = user_library_path(owner, bookshelf_id: first_entry.bookshelf_id, sort: "manual")
    visit path
    expect(page).to have_css("[data-bookshelf-entry-id][data-bookshelf-entries-sort-handle]", count: 3)
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']")
    page.execute_script(<<~JS, shelf_list)
      window.desktopSortable = window.Stimulus.getControllerForElementAndIdentifier(
        arguments[0].closest("[data-controller~='bookshelf-entries-sort']"), "bookshelf-entries-sort"
      ).sortable
    JS

    page.current_window.resize_to(390, 700)
    cover = cover_for(first_entry)
    expect(page).to have_current_path(path)
    mouse = page.driver.browser.action
    mouse.click_and_hold(cover.native).pause(duration: 0.4).perform
    expect(page).to have_no_css("[data-touch-reorder], [data-reorder-selected], .bookshelf-reorder-held")
    mouse.release.perform
    expect(page).to have_css("dialog[open]", text: first_entry.book.title)
    find("dialog[open] button[data-action='book-modal#close']").click

    page.current_window.resize_to(1280, 900)
    expect(page).to have_current_path(path)
    expect(page.evaluate_script(<<~JS, shelf_list)).to be(true)
      window.desktopSortable === window.Stimulus.getControllerForElementAndIdentifier(
        arguments[0].closest("[data-controller~='bookshelf-entries-sort']"), "bookshelf-entries-sort"
      ).sortable && window.desktopSortable.option("delay") === 0
    JS
  end

  it "opens on a touch tap and saves a cross-row touch drag once without opening a dialog" do
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    fourth_entry = owner.bookshelf_entries.create!(book: Book.create!(title: "Fourth order book"))
    original_order = [ first_entry.id, second_entry.id, third_entry.id, fourth_entry.id ]
    reordered = [ second_entry.id, third_entry.id, fourth_entry.id, first_entry.id ]
    path = user_library_path(owner, bookshelf_id: first_entry.bookshelf_id, sort: "manual")
    visit path

    list = shelf_list
    page.execute_script("arguments[0].scrollIntoView({ block: 'start', behavior: 'instant' })", list)
    touch(cover_center(cover_for(first_entry)))
    expect(page).to have_css("dialog[open]", text: first_entry.book.title)
    find("dialog[open] button[data-action='book-modal#close']").click

    touch(cover_center(cover_for(first_entry)), hold: 0.45)
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_css("[data-bookshelf-entry-id='#{first_entry.id}'][data-reorder-selected]")
    expect(page).to have_css("[data-bookshelf-entries-sort-target='selectedStatus']", text: first_entry.book.title)
    expect(saved_entry_ids).to eq(original_order)
    expect(page.evaluate_script(<<~JS)).to be(true)
      document.querySelector('[data-bookshelf-entries-sort-target="spacer"]').getBoundingClientRect().height >=
        document.querySelector('[data-bookshelf-entries-sort-target="controls"]').getBoundingClientRect().height
    JS

    touch(cover_center(cover_for(second_entry)), hold: 0.45)
    expect(page).to have_css("[data-bookshelf-entry-id='#{second_entry.id}'][data-reorder-selected]")
    expect(page).to have_no_css("[data-bookshelf-entry-id='#{first_entry.id}'][data-reorder-selected]")
    click_button I18n.t("users.library.transfer.clear_selection")
    expect(page).to have_no_css("[data-reorder-selected], [data-bookshelf-entries-sort-target='controls'], [data-bookshelf-entries-sort-target='spacer']")

    page.execute_script(<<~JS)
      window.reorderRequests = 0
      const originalFetch = window.fetch
      window.fetch = (...args) => {
        if (args[0] !== "#{reorder_bookshelf_entries_path}") return originalFetch.apply(window, args)
        window.reorderRequests += 1
        return new Promise((resolve, reject) => {
          window.finishReorder = () => originalFetch.apply(window, args).then(resolve, reject)
        })
      }
    JS

    page.execute_script("arguments[0].scrollIntoView({ block: 'start', behavior: 'instant' })", list)
    origin = cover_center(cover_for(first_entry))
    lower_row = cover_center(cover_for(fourth_entry)).last
    start_drag_at = [ cover_center(cover_for(second_entry)).first, lower_row ]
    destination = [ cover_center(cover_for(third_entry)).first, lower_row ]
    expect(lower_row).to be > origin.last
    dragged_entry = "[data-bookshelf-entries-sort-target='list'] > [data-bookshelf-entry-id='#{first_entry.id}']"
    last_entry = "#{dragged_entry}:last-child"

    page.execute_script(<<~JS, list)
      window.startedShelfDrag = new Promise((resolve) => {
        arguments[0].addEventListener("start", ({ item }) => resolve(item.dataset.bookshelfEntryId), { once: true })
      })
    JS

    with_active_touch(origin) do
      expect(page).to have_css("#{dragged_entry}[data-reorder-selected]")
      # In Sortable's fallback mode, the first move starts the drag and the next sets the drop position.
      dispatch_touch("touchMove", start_drag_at)
      expect(page.evaluate_async_script("window.startedShelfDrag.then(arguments[0])")).to eq(first_entry.id.to_s)
      expect(page.evaluate_script("document.elementFromPoint(arguments[1], arguments[2]) === arguments[0]", list, *destination)).to be(true)
      dispatch_touch("touchMove", destination)
      expect(page).to have_css(last_entry)
    end

    expect(page).to have_css(last_entry)
    expect(visible_entry_ids).to eq(reordered)
    expect(page.evaluate_script("window.reorderRequests")).to eq(1)
    expect(saved_entry_ids).to eq(original_order)
    expect(page).to have_no_css("dialog[open]")
    move_up = I18n.t("users.profile.bookshelf_sort.move_up", title: first_entry.book.title)
    expect(page).to have_button(move_up, disabled: true, enable_aria_label: true)
    touch(origin, to: destination, hold: 0.45)
    expect(visible_entry_ids).to eq(reordered)
    expect(page.evaluate_script("window.reorderRequests")).to eq(1)

    page.execute_script(<<~JS, list)
      window.touchSortable = window.Stimulus.getControllerForElementAndIdentifier(
        arguments[0].closest("[data-controller~='bookshelf-entries-sort']"), "bookshelf-entries-sort"
      ).sortable
      window.finishReorder()
    JS
    expect(page).to have_button(move_up, disabled: false, enable_aria_label: true)
    expect(page).to have_css("[data-bookshelf-entry-id='#{first_entry.id}'][data-reorder-selected]")
    expect(saved_entry_ids).to eq(reordered)

    page.current_window.resize_to(850, 600)
    expect(page).to have_current_path(path)
    expect(page.evaluate_script(<<~JS, shelf_list)).to be(true)
      window.touchSortable === window.Stimulus.getControllerForElementAndIdentifier(
        arguments[0].closest("[data-controller~='bookshelf-entries-sort']"), "bookshelf-entries-sort"
      ).sortable && window.touchSortable.option("delay") === 350
    JS
    page.refresh
    expect(page).to have_no_css("[data-reorder-selected], [data-bookshelf-entries-sort-target='controls']")
    expect(visible_entry_ids).to eq(reordered)
  end

  it "starts a hold on the rendered cover but ignores the empty shelf slot above it" do
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    image = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="80"><rect width="200" height="80" fill="navy"/></svg>'
    first_entry.book.update_columns(thumbnail: "data:image/svg+xml,#{ERB::Util.url_encode(image)}")
    visit user_library_path(owner, sort: "manual")
    cover = cover_for(first_entry)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center', behavior: 'instant' })", cover)
    cover.find("img") { |img| page.evaluate_script("arguments[0].naturalWidth > 0", img) }
    blank, painted = page.evaluate_script(<<~JS, cover)
      (() => {
        const rect = arguments[0].getBoundingClientRect()
        const x = Math.round(rect.left + rect.width / 2)
        return [[x, Math.ceil(rect.top) + 5], [x, Math.floor(rect.bottom) - 5]]
      })()
    JS

    begin
      dispatch_touch("touchStart", blank)
      page.evaluate_async_script("setTimeout(arguments[0], 450)")
      expect(page).to have_no_css("[data-reorder-selected], [data-bookshelf-entries-sort-target='controls']")
    ensure
      dispatch_touch("touchCancel")
    end

    touch(painted, hold: 0.45)
    expect(page).to have_css("[data-bookshelf-entry-id='#{first_entry.id}'][data-reorder-selected]")
    expect(page).to have_no_css("dialog[open]")
    outline_style, top, expected_top, left, bottom = page.evaluate_script(<<~JS, cover)
      (() => {
        const cover = arguments[0]
        const rect = cover.getBoundingClientRect()
        const outline = getComputedStyle(cover, "::after")
        return [outline.outlineStyle, parseFloat(outline.top), rect.height - rect.width * 80 / 200,
          parseFloat(outline.left), parseFloat(outline.bottom)]
      })()
    JS
    expect(outline_style).to eq("solid")
    expect(top).to be_within(1).of(expected_top)
    expect(top).to be > 5
    expect([ left, bottom ]).to eq([ 0, 0 ])
  end

  it "restores the preceding order before reporting failed saves and reloads the actual server order" do
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    %w[http network lost_response].each do |failure|
      visit user_library_path(owner, sort: "manual")
      original_order = saved_entry_ids
      shelf_list
      page.execute_script(<<~JS)
        const originalFetch = window.fetch
        const originalAlert = window.alert
        window.alert = (message) => {
          const list = document.querySelector('[data-bookshelf-entries-sort-target="list"]')
          sessionStorage.setItem('orderBeforeReload', JSON.stringify(
            Array.from(list.children, entry => Number(entry.dataset.bookshelfEntryId))
          ))
          originalAlert(message)
        }
        window.fetch = (...args) => {
          if (args[0] !== "#{reorder_bookshelf_entries_path}") return originalFetch.apply(window, args)
          if ("#{failure}" === "http") return Promise.resolve(new Response("{}", { status: 422 }))
          if ("#{failure}" === "network") return Promise.reject(new TypeError("Offline"))
          return originalFetch.apply(window, args).then(() => { throw new TypeError("Response lost") })
        }
      JS

      choose_book(first_entry)
      accept_alert(I18n.t("bookshelf_entries.alerts.reorder_failed")) do
        click_button I18n.t("users.profile.bookshelf_sort.move_down", title: first_entry.book.title), enable_aria_label: true
      end
      expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']")
      expect(page.evaluate_script("JSON.parse(sessionStorage.getItem('orderBeforeReload'))")).to eq(original_order)
      expect(visible_entry_ids).to eq(saved_entry_ids)
      if failure == "lost_response"
        expect(saved_entry_ids).to eq([ second_entry.id, first_entry.id, third_entry.id ])
      else
        expect(saved_entry_ids).to eq(original_order)
      end
    end
  end

  it "omits the mobile reorder controls for other sorts, one book, and another user's library" do
    visit user_library_path(owner, sort: "recent")
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']", visible: :all)

    single_shelf = owner.bookshelves.create!(name: "Single book shelf", visibility: :public)
    owner.bookshelf_entries.create!(bookshelf: single_shelf, book: Book.create!(title: "Only book"))
    visit user_library_path(owner, bookshelf_id: single_shelf.id, sort: "manual")
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']", visible: :all)

    visitor = User.create!(name: "Order visitor", email: "order-visitor@example.com", password: "password123!")
    BookFriendship.create!(requester: visitor, addressee: owner, status: :accepted)
    login_as visitor, scope: :user
    visit user_library_path(owner, sort: "manual")
    expect(page).to have_current_path(user_library_path(owner, sort: "manual"))
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']", visible: :all)
  end
end
