require "rails_helper"

RSpec.describe "Relationship management", type: :system do
  include Warden::Test::Helpers

  let!(:viewer) { User.create!(name: "Viewer", email: "relationships-viewer-system@example.com", password: "password123!") }
  let!(:friend) { User.create!(name: "긴이름" * 15, handle: "long_public_friend_handle", email: "relationships-friend-system@example.com", password: "password123!") }
  let!(:second_friend) { User.create!(name: "Second friend", email: "relationships-second-system@example.com", password: "password123!") }
  let!(:requester) { User.create!(name: "Request reader", handle: "incoming_reader", email: "relationships-incoming-system@example.com", password: "password123!") }
  let!(:rejected_requester) { User.create!(name: "Reject reader", email: "relationships-reject-system@example.com", password: "password123!") }
  let!(:addressee) { User.create!(name: "Sent reader", email: "relationships-sent-system@example.com", password: "password123!") }
  let!(:followee) { User.create!(name: "Followed reader", email: "relationships-followee-system@example.com", password: "password123!") }
  let!(:follower) { User.create!(name: "Subscriber", email: "relationships-follower-system@example.com", password: "password123!") }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 900 ]
    BookFriendship.create!(requester: viewer, addressee: friend, status: :accepted)
    BookFriendship.create!(requester: second_friend, addressee: viewer, status: :accepted)
    BookFriendship.create!(requester: requester, addressee: viewer)
    BookFriendship.create!(requester: rejected_requester, addressee: viewer)
    BookFriendship.create!(requester: viewer, addressee: addressee)
    viewer.active_follows.create!(followee: followee)
    follower.active_follows.create!(followee: viewer)
    login_as viewer, scope: :user
  end

  after { Warden.test_reset! }

  def select_tab(tab)
    find("#relationships-tab-#{tab}").click
    expect(page).to have_css("#relationships-tab-#{tab}[aria-current='page']")
  end

  [ [ 390, 1 ], [ 768, 2 ], [ 1440, 2 ] ].each do |width, columns|
    it "shows #{columns} grid columns at #{width}px and keeps long identities within their cards" do
      page.driver.browser.manage.window.resize_to(width, 900)
      visit account_relationships_path

      expect(page).to have_css("#relationships-grid article", count: 2)
      grid = find("#relationships-grid")
      expect(grid.evaluate_script("getComputedStyle(this).gridTemplateColumns.split(' ').length")).to eq(columns)
      within(grid) do
        expect(page).to have_text(friend.name)
        expect(page).to have_text("@#{friend.handle}")
      end
      identity = grid.find("a[href='#{user_path(friend)}']")
      expect(identity["title"]).to eq(friend.name)
      name = identity.find("p", text: friend.name, exact_text: true)
      expect(name.text).to eq(friend.name)
      expect(name.evaluate_script("getComputedStyle(this).textOverflow")).to eq("ellipsis")
      expect(name.evaluate_script("this.scrollWidth > this.clientWidth")).to be(true)
      all("#relationships-grid article").each do |card|
        expect(card.evaluate_script("getComputedStyle(this).flexDirection")).to eq("row")
        expect(card.evaluate_script("this.scrollWidth <= this.clientWidth")).to be(true)
      end
      if width == 390
        tabs = find("nav[aria-label='#{I18n.t("relationships.tabs_label")}']")
        expect(tabs.evaluate_script("this.scrollWidth > this.clientWidth")).to be(true)
      end
    end
  end

  it "keeps both received request buttons on one line beside a truncated name on mobile" do
    requester.update!(name: "신청한사용자의긴이름" * 8)
    visit account_relationships_path(tab: "received_book_friend_requests")

    card = find("#relationships-grid article", text: requester.name)
    identity = card.find("a[href='#{user_path(requester)}']")
    expect(identity["title"]).to eq(requester.name)
    expect(identity.find("p", text: requester.name, exact_text: true).text).to eq(requester.name)
    within(card) do
      expect(page).to have_button(I18n.t("users.actions.accept_book_friend"))
      expect(page).to have_button(I18n.t("users.actions.reject_book_friend_request"))
    end
    layout = card.evaluate_script(<<~JS)
      (() => {
        const buttons = Array.from(this.querySelectorAll('button'))
        const rects = buttons.map(button => button.getBoundingClientRect())
        const avatar = this.querySelector('img').getBoundingClientRect()
        return {
          sameRow: Math.abs(rects[0].top - rects[1].top) < 1,
          besideIdentity: rects[0].left >= this.querySelector('a').getBoundingClientRect().right,
          centered: Math.abs((rects[0].top + rects[0].bottom) / 2 - (avatar.top + avatar.bottom) / 2) < 1,
          noWrap: buttons.every(button => getComputedStyle(button).whiteSpace === 'nowrap'),
          fits: this.scrollWidth <= this.clientWidth
        }
      })()
    JS
    expect(layout).to eq("sameRow" => true, "besideIdentity" => true, "centered" => true, "noWrap" => true, "fits" => true)
  end

  it "searches and manages requests and relationships while updating the selected tab and counts" do
    visit account_relationships_path
    select_tab("received_book_friend_requests")
    fill_in I18n.t("relationships.search.label"), with: requester.name
    click_button I18n.t("relationships.search.submit")
    expect(page).to have_css("#relationships-grid article", count: 1)
    within("#relationships-grid") { click_button I18n.t("users.actions.accept_book_friend") }
    expect(page).to have_css("#relationships-count-received_book_friend_requests", text: "1", exact_text: true)
    expect(page).to have_css("#relationships-count-book_friends", text: "3", exact_text: true)
    expect(page).to have_field(I18n.t("relationships.search.label"), with: requester.name)
    expect(page).to have_css("#relationships-tab-received_book_friend_requests[aria-current='page']")

    select_tab("book_friends")
    within("#relationships-grid") { click_button I18n.t("users.actions.remove_book_friend") }
    expect(page).to have_css("#relationships-count-book_friends", text: "2", exact_text: true)
    fill_in I18n.t("relationships.search.label"), with: ""
    click_button I18n.t("relationships.search.submit")
    expect(page).to have_css("#relationships-grid article", count: 2)
    select_tab("received_book_friend_requests")
    within("#relationships-grid") { click_button I18n.t("users.actions.reject_book_friend_request") }
    expect(page).to have_css("#relationships-count-received_book_friend_requests", text: "0", exact_text: true)

    select_tab("sent_book_friend_requests")
    within("#relationships-grid") { click_button I18n.t("users.actions.cancel_book_friend_request") }
    expect(page).to have_css("#relationships-count-sent_book_friend_requests", text: "0", exact_text: true)

    select_tab("following_users")
    within("#relationships-grid") { click_button I18n.t("users.actions.unfollow") }
    expect(page).to have_css("#relationships-count-following_users", text: "0", exact_text: true)
    select_tab("followers")
    within("#relationships-grid") do
      expect(page).to have_link(href: user_path(follower))
      expect(page).to have_no_button
    end
  end
end
