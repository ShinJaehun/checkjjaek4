require "rails_helper"

RSpec.describe "Feed infinite scroll", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Scroll reader", email: "feed-scroll@example.com", password: "password123!") }
  let!(:posts) do
    Array.new(25) { |index| user.jjaeks.create!(content: "SCROLL_POST_#{index}", created_at: Time.zone.parse("2026-10-19 12:00:00")) }
  end

  before do
    driven_by :selenium, using: :headless_chrome
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  it "automatically appends the final page once and keeps inline comments working" do
    posts.first.comments.create!(user:, content: "COMMENT_ON_APPENDED_CARD")
    visit root_path
    expect(page).to have_css("#feed-items > article", count: 20)
    find("textarea[name='jjaek[content]']").set("UNSUBMITTED_FEED_DRAFT")
    page.execute_script(<<~JS)
      window.originalFeedForm = document.querySelector("textarea[name='jjaek[content]']").form
      window.originalFeedCard = document.querySelector("#feed-items > article")
    JS

    page.execute_script("document.getElementById('feed-pagination').scrollIntoView()")

    expect(page).to have_css("#feed-items > article", count: 25)
    expect(page).to have_css("[data-feed-end]")
    expect(page).to have_no_css("#feed-pagination a")
    ids = page.all("#feed-items > article").map { |node| node["id"] }
    expect(ids.uniq.size).to eq(25)
    expect(page).to have_current_path(root_path)
    expect(find("textarea[name='jjaek[content]']").value).to eq("UNSUBMITTED_FEED_DRAFT")
    expect(page.evaluate_script("window.originalFeedForm === document.querySelector(\"textarea[name='jjaek[content]']\").form")).to be(true)
    expect(page.evaluate_script("window.originalFeedCard === document.querySelector('#feed-items > article')")).to be(true)

    within("#jjaek_#{posts.first.id}") { click_link I18n.t("comments.actions.view_inline") }
    expect(page).to have_css("#comments_panel_home_jjaek_#{posts.first.id}", text: "COMMENT_ON_APPENDED_CARD")
  end

  it "pauses automatic requests after an error and lets the same next link retry" do
    visit root_path
    page.execute_script(<<~JS)
      const originalFetch = window.fetch.bind(window)
      window.feedRequests = 0
      window.fetch = (input, options) => {
        if (String(input).includes("cursor=")) {
          window.feedRequests += 1
          if (window.feedRequests === 1) return Promise.resolve(new Response("", { status: 503 }))
        }
        return originalFetch(input, options)
      }
      document.getElementById("feed-pagination").scrollIntoView()
    JS

    expect(page).to have_css("[data-infinite-scroll-target='error']", text: I18n.t("feeds.failed"), visible: true)
    expect(page).to have_css("#feed-items > article", count: 20)
    expect(page.evaluate_script("window.feedRequests")).to eq(1)
    click_link I18n.t("feeds.next")

    expect(page).to have_css("#feed-items > article", count: 25)
    expect(page).to have_css("[data-feed-end]")
    expect(page.evaluate_script("window.feedRequests")).to eq(2)
  end
end
