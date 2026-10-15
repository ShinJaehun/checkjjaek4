require "rails_helper"

RSpec.describe "Book reading state", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Autosave reader", email: "autosave-system@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "자동 저장 책", authors_text: "저자") }
  let!(:entry) { user.bookshelf_entries.create!(book: book, status: :reading) }
  let!(:first_sticker) { StickerDefinition.create!(key: "autosave_first", name: "추천") }
  let!(:second_sticker) { StickerDefinition.create!(key: "autosave_second", name: "감동") }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    login_as user, scope: :user
    visit book_path(book)
    expect(page).to have_css('[data-controller="reading-state"]')
    expect(page).to have_checked_field(I18n.t("bookshelf_entries.statuses.reading"), visible: :all)
  end

  after { Warden.test_reset! }

  it "clears the selected status on a second click and keeps stickers" do
    check first_sticker.name, allow_label_click: true
    expect(page).to have_text(I18n.t("books.show.saved_state"))
    uncheck I18n.t("bookshelf_entries.statuses.reading"), allow_label_click: true
    expect(page).to have_no_css('[data-controller="reading-state"][aria-busy="true"]')
    expect(entry.reload.status).to be_nil
    expect(entry.sticker_definition_ids).to eq([ first_sticker.id ])
    expect(page).to have_no_css('[data-reading-state-target="status"]:checked')
    expect(entry.book_activities).to be_empty

    uncheck first_sticker.name, allow_label_click: true
    expect(page).to have_no_css('[data-controller="reading-state"][aria-busy="true"]')
    expect(entry.reload.sticker_definition_ids).to be_empty

    check I18n.t("bookshelf_entries.statuses.finished"), allow_label_click: true
    expect(page).to have_no_css('[data-controller="reading-state"][aria-busy="true"]')
    expect(entry.reload.status).to eq("finished")
  end

  it "serializes rapid status and sticker clicks and persists the final selection" do
    page.execute_script <<~JS
      const originalFetch = window.fetch.bind(window)
      window.readingRequests = []
      window.activeReadingRequests = 0
      window.maxReadingRequests = 0
      window.fetch = async (url, options) => {
        if (options?.method !== "PATCH") return originalFetch(url, options)
        window.readingRequests.push(options.body.toString())
        window.activeReadingRequests += 1
        window.maxReadingRequests = Math.max(window.maxReadingRequests, window.activeReadingRequests)
        await new Promise(resolve => setTimeout(resolve, 100))
        const response = await originalFetch(url, options)
        window.activeReadingRequests -= 1
        return response
      }
      const panel = document.querySelector('[data-controller="reading-state"]')
      panel.querySelector('[data-reading-state-target="status"][value="finished"]').click()
      panel.querySelector('#reading_sticker_#{first_sticker.id}').click()
      panel.querySelector('#reading_sticker_#{second_sticker.id}').click()
      panel.querySelector('#reading_sticker_#{first_sticker.id}').click()
      panel.querySelector('[data-reading-state-target="status"][value="wish"]').click()
    JS

    expect(page).to have_text(I18n.t("books.show.saved_state"))
    expect(entry.reload.status).to eq("wish")
    expect(entry.sticker_definition_ids).to eq([ second_sticker.id ])
    expect(page).to have_checked_field(I18n.t("bookshelf_entries.statuses.wish"), visible: :all)
    expect(page).to have_checked_field(second_sticker.name, visible: :all)
    expect(page).to have_unchecked_field(first_sticker.name, visible: :all)
    expect(page.evaluate_script("window.maxReadingRequests")).to eq(1)
    requests = page.evaluate_script("window.readingRequests").map { |body| Rack::Utils.parse_nested_query(body) }
    expect(requests).to eq([
      { "bookshelf_entry" => { "status" => "finished" } },
      { "sticker_definition_id" => first_sticker.id.to_s, "sticker_selected" => "true" },
      { "sticker_definition_id" => second_sticker.id.to_s, "sticker_selected" => "true" },
      { "sticker_definition_id" => first_sticker.id.to_s, "sticker_selected" => "false" },
      { "bookshelf_entry" => { "status" => "wish" } }
    ])
    expect(entry.book_activities).to be_empty
  end

  it "restores saved selections, cancels queued clicks on failure, and allows retry" do
    page.execute_script <<~JS
      window.originalReadingFetch = window.fetch.bind(window)
      window.failedReadingRequests = 0
      window.fetch = async (url, options) => {
        if (options?.method !== "PATCH") return window.originalReadingFetch(url, options)
        window.failedReadingRequests += 1
        await new Promise(resolve => setTimeout(resolve, 100))
        return new Response(JSON.stringify({ error: "Save failed" }), {
          status: 422, headers: { "Content-Type": "application/json" }
        })
      }
      const panel = document.querySelector('[data-controller="reading-state"]')
      panel.querySelector('[data-reading-state-target="status"][value="finished"]').click()
      panel.querySelector('#reading_sticker_#{first_sticker.id}').click()
    JS

    expect(page).to have_text(I18n.t("books.show.save_state_failed"))
    expect(page).to have_checked_field(I18n.t("bookshelf_entries.statuses.reading"), visible: :all)
    expect(page).to have_unchecked_field(first_sticker.name, visible: :all)
    expect(page.evaluate_script("window.failedReadingRequests")).to eq(1)
    expect(entry.reload.status).to eq("reading")
    expect(entry.sticker_definition_ids).to be_empty

    page.execute_script("window.fetch = window.originalReadingFetch")
    check I18n.t("bookshelf_entries.statuses.finished"), allow_label_click: true
    expect(page).to have_text(I18n.t("books.show.saved_state"))
    expect(entry.reload.status).to eq("finished")
  end
  it "keeps the last successful save when a later network request fails" do
    check I18n.t("bookshelf_entries.statuses.finished"), allow_label_click: true
    expect(page).to have_text(I18n.t("books.show.saved_state"))

    page.execute_script <<~JS
      const originalFetch = window.fetch.bind(window)
      window.fetch = async (url, options) => {
        if (options?.method !== "PATCH") return originalFetch(url, options)
        await new Promise(resolve => setTimeout(resolve, 100))
        throw new TypeError("Network unavailable")
      }
      document.querySelector('#reading_sticker_#{first_sticker.id}').click()
      document.querySelector('#reading_sticker_#{second_sticker.id}').click()
    JS

    expect(page).to have_text(I18n.t("books.show.save_state_failed"))
    expect(page).to have_checked_field(I18n.t("bookshelf_entries.statuses.finished"), visible: :all)
    expect(page).to have_unchecked_field(first_sticker.name, visible: :all)
    expect(page).to have_unchecked_field(second_sticker.name, visible: :all)
    expect(entry.reload.status).to eq("finished")
    expect(entry.sticker_definition_ids).to be_empty
  end

end
