require "rails_helper"

RSpec.describe "Mobile bookshelf ordering", type: :system do
  include Warden::Test::Helpers

  let(:owner) { User.create!(name: "Order owner", email: "order-owner@example.com", password: "password123!") }
  let!(:first_entry) { owner.bookshelf_entries.create!(book: Book.create!(title: "First order book")) }
  let!(:second_entry) { owner.bookshelf_entries.create!(book: Book.create!(title: "Second order book")) }
  let!(:third_entry) { owner.bookshelf_entries.create!(book: Book.create!(title: "Third order book")) }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 700 ]
    page.driver.browser.manage.window.resize_to(390, 700)
    login_as owner, scope: :user
  end

  after { Warden.test_reset! }

  def visible_entry_ids
    all("[data-bookshelf-entries-sort-target='list'] > [data-bookshelf-entry-id]").map { |card| card["data-bookshelf-entry-id"].to_i }
  end

  it "cancels draft moves or applies their final order once while keeping desktop drag handles" do
    visit user_library_path(owner, sort: "manual")
    page.execute_script(<<~JS)
      window.reorderRequests = 0
      const originalFetch = window.fetch
      window.fetch = (...args) => {
        if (args[0] === "#{reorder_bookshelf_entries_path}") window.reorderRequests += 1
        return originalFetch.apply(window, args)
      }
    JS

    expect(visible_entry_ids).to eq([ first_entry.id, second_entry.id, third_entry.id ])
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.reorder_start"))
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']", visible: true)
    click_button I18n.t("users.profile.bookshelf_sort.reorder_start")

    expect(page).to have_css("[data-bookshelf-entries-sort-target='editingStatus']", visible: true, text: I18n.t("users.profile.bookshelf_sort.reorder_editing"))
    expect(page).to have_css("[data-bookshelf-entries-sort-target='actionBar']", visible: true)
    expect(find("[data-bookshelf-entries-sort-target='actionBar']")[:class]).to include("fixed")
    expect(page).to have_css("[data-bookshelf-entries-sort-target='bottomSpacer']", visible: true)
    expect(page.evaluate_script(<<~JS)).to be(true)
      document.querySelector('[data-bookshelf-entries-sort-target=bottomSpacer]').offsetHeight >=
        document.querySelector('[data-bookshelf-entries-sort-target=actionBar]').offsetHeight
    JS
    within("[data-controller='bookshelf-entries-sort'] > header") do
      expect(page).to have_no_button(I18n.t("users.profile.bookshelf_sort.reorder_cancel"))
      expect(page).to have_no_button(I18n.t("users.profile.bookshelf_sort.reorder_apply"))
    end
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.reorder_cancel"))
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.reorder_apply"), disabled: true)
    expect(page).to have_button(
      I18n.t("users.profile.bookshelf_sort.move_up", title: first_entry.book.title),
      disabled: true,
      enable_aria_label: true
    )
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.move_down", title: third_entry.book.title), disabled: true, enable_aria_label: true)
    expect(page).to have_link(first_entry.book.title)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('[data-bookshelf-entries-sort-target=controls]')).position")).to eq("absolute")

    click_button I18n.t("users.profile.bookshelf_sort.move_down", title: first_entry.book.title), enable_aria_label: true
    expect(visible_entry_ids).to eq([ second_entry.id, first_entry.id, third_entry.id ])
    click_button I18n.t("users.profile.bookshelf_sort.move_up", title: first_entry.book.title), enable_aria_label: true
    expect(visible_entry_ids).to eq([ first_entry.id, second_entry.id, third_entry.id ])
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.reorder_apply"), disabled: true)

    click_button I18n.t("users.profile.bookshelf_sort.move_down", title: first_entry.book.title), enable_aria_label: true
    click_button I18n.t("users.profile.bookshelf_sort.move_up", title: third_entry.book.title), enable_aria_label: true
    expect(visible_entry_ids).to eq([ second_entry.id, third_entry.id, first_entry.id ])
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.move_down", title: third_entry.book.title), disabled: false, enable_aria_label: true)
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.reorder_apply"), disabled: false)
    expect(page.evaluate_script("window.reorderRequests")).to eq(0)
    expect(owner.bookshelf_entries.where(bookshelf_id: first_entry.bookshelf_id).order(:position, :id).pluck(:id)).to eq([ first_entry.id, second_entry.id, third_entry.id ])

    click_button I18n.t("users.profile.bookshelf_sort.reorder_cancel")
    expect(visible_entry_ids).to eq([ first_entry.id, second_entry.id, third_entry.id ])
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']", visible: true)
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='actionBar']", visible: true)
    expect(page.evaluate_script("window.reorderRequests")).to eq(0)

    click_button I18n.t("users.profile.bookshelf_sort.reorder_start")
    click_button I18n.t("users.profile.bookshelf_sort.move_down", title: first_entry.book.title), enable_aria_label: true
    page.driver.browser.manage.window.resize_to(1280, 900)
    expect(page).to have_css("[data-bookshelf-entries-sort-target='list'] > [data-bookshelf-entry-id='#{first_entry.id}']:first-child")
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='actionBar']", visible: true)
    page.driver.browser.manage.window.resize_to(390, 700)
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.reorder_start"))
    expect(page.evaluate_script("window.reorderRequests")).to eq(0)

    click_button I18n.t("users.profile.bookshelf_sort.reorder_start")
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.reorder_apply"), disabled: true)
    click_button I18n.t("users.profile.bookshelf_sort.move_down", title: first_entry.book.title), enable_aria_label: true
    click_button I18n.t("users.profile.bookshelf_sort.move_up", title: third_entry.book.title), enable_aria_label: true
    expect(visible_entry_ids).to eq([ second_entry.id, third_entry.id, first_entry.id ])
    expect(page.evaluate_script("window.reorderRequests")).to eq(0)

    click_button I18n.t("users.profile.bookshelf_sort.reorder_apply")
    expect(page).to have_button(I18n.t("users.profile.bookshelf_sort.reorder_start"))
    expect(page.evaluate_script("window.reorderRequests")).to eq(1)
    expect(owner.bookshelf_entries.where(bookshelf_id: first_entry.bookshelf_id).order(:position, :id).pluck(:id)).to eq(visible_entry_ids)

    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']", visible: true)
    page.refresh
    expect(visible_entry_ids).to eq([ second_entry.id, third_entry.id, first_entry.id ])

    page.driver.browser.manage.window.resize_to(1280, 900)
    expect(page).to have_no_button(I18n.t("users.profile.bookshelf_sort.reorder_start"))
    expect(page).to have_css("[data-bookshelf-entry-id][data-bookshelf-entries-sort-handle]", count: 3)
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']", visible: true)
  end

  it "omits mobile reorder controls for other sorts, a single book, and another user's library" do
    visit user_library_path(owner, sort: "recent")
    expect(page).to have_no_button(I18n.t("users.profile.bookshelf_sort.reorder_start"))
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']")

    single_shelf = owner.bookshelves.create!(name: "Single book shelf", visibility: :public)
    owner.bookshelf_entries.create!(bookshelf: single_shelf, book: Book.create!(title: "Only book"))
    visit user_library_path(owner, bookshelf_id: single_shelf.id, sort: "manual")
    expect(page).to have_no_button(I18n.t("users.profile.bookshelf_sort.reorder_start"))
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']")

    visitor = User.create!(name: "Order visitor", email: "order-visitor@example.com", password: "password123!")
    login_as visitor, scope: :user
    visit user_library_path(owner, sort: "manual")
    expect(page).to have_no_button(I18n.t("users.profile.bookshelf_sort.reorder_start"))
    expect(page).to have_no_css("[data-bookshelf-entries-sort-target='controls']")
  end
end
