require "rails_helper"

RSpec.describe "Relationships", type: :request do
  let!(:viewer) { User.create!(name: "Viewer", email: "viewer-relationships@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:received_requester) { User.create!(name: "Received Requester", email: "received-requester-relationships@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:sent_addressee) { User.create!(name: "Sent Addressee", email: "sent-addressee-relationships@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book_friend) { User.create!(name: "Book Friend", email: "book-friend-relationships@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:followee) { User.create!(name: "Followee", email: "followee-relationships@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:follower) { User.create!(name: "Follower", email: "follower-relationships@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:hidden_requester) { User.create!(name: "Hidden Requester", email: "hidden-requester-relationships@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:hidden_addressee) { User.create!(name: "Hidden Addressee", email: "hidden-addressee-relationships@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:hidden_book_friend) { User.create!(name: "Hidden Book Friend", email: "hidden-book-friend-relationships@example.com", password: "password123!", password_confirmation: "password123!") }

  before do
    received_requester.requested_book_friendships.create!(addressee: viewer)
    viewer.requested_book_friendships.create!(addressee: sent_addressee)
    BookFriendship.create!(requester: viewer, addressee: book_friend, status: :accepted)
    viewer.active_follows.create!(followee: followee)
    follower.active_follows.create!(followee: viewer)

    hidden_requester.requested_book_friendships.create!(addressee: hidden_addressee)
    BookFriendship.create!(requester: hidden_requester, addressee: hidden_book_friend, status: :accepted)
    hidden_requester.active_follows.create!(followee: hidden_addressee)
  end

  def parse_html
    Nokogiri::HTML.parse(response.body)
  end

  it "redirects guests to sign in" do
    get account_relationships_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not show relationship notification UI to guests" do
    get new_user_session_path

    expect(response.body).not_to include("relationship-notification-badge")
    expect(response.body).not_to include(account_relationships_path(tab: "received_book_friend_requests", anchor: "received-book-friend-requests"))
  end

  it "allows signed-in users to open the relationship hub" do
    sign_in viewer

    get account_relationships_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("relationships.title"))
    expect(response.body).to include(I18n.t("relationships.description"))
    expect(parse_html.at_css("#book-friends h2").text).to eq(I18n.t("relationships.tabs.book_friends"))
    expect(parse_html.at_css("a[aria-current='page']")["id"]).to eq("relationships-tab-book_friends")
    expect(response.body).to include("user_profile_")
    expect(response.body).to include("_128")
  end

  it "does not show the old relationship notification badge in the navigation" do
    sign_in viewer

    get root_path

    expect(parse_html.at_css("#relationship-notification-badge")).to be_nil
  end

  it "keeps account actions out of the navigation and links the current user to their profile" do
    sign_in viewer

    get root_path

    nav = parse_html.at_css("nav")
    expect(nav.at_css(%(a[href="#{account_relationships_path}"]))).to be_nil
    expect(nav.at_css(%(a[href="#{account_settings_path}"]))).to be_nil
    profile_link = nav.at_css(%(a[href="#{user_path(viewer)}"]))
    expect(profile_link).to be_present
    expect(profile_link.at_css(%(img[alt="#{viewer.name}"]))).to be_present
    expect(profile_link.text).to include(viewer.name)
  end

  it "keeps account actions out of the navigation when there are no pending received requests" do
    BookFriendship.where(addressee: viewer, status: :pending).delete_all
    sign_in viewer

    get root_path

    expect(parse_html.at_css("#relationship-notification-badge")).to be_nil
    nav = parse_html.at_css("nav")
    expect(nav.at_css(%(a[href="#{account_relationships_path}"]))).to be_nil
    expect(nav.at_css(%(a[href="#{account_settings_path}"]))).to be_nil
  end

  it "shows received book-friend requests to the addressee" do
    sign_in viewer

    get account_relationships_path, params: { tab: "received_book_friend_requests" }

    expect(response.body).to include("Received Requester")
  end

  it "shows sent book-friend requests to the requester" do
    sign_in viewer

    get account_relationships_path, params: { tab: "sent_book_friend_requests" }

    expect(response.body).to include("Sent Addressee")
  end

  it "shows accepted book friends" do
    sign_in viewer

    get account_relationships_path

    expect(response.body).to include("Book Friend")
  end

  it "shows users the viewer follows" do
    sign_in viewer

    get account_relationships_path, params: { tab: "following_users" }

    expect(response.body).to include("Followee")
  end

  it "shows users following the viewer" do
    sign_in viewer

    get account_relationships_path, params: { tab: "followers" }

    expect(response.body).to include("Follower")
    expect(parse_html.at_css("#followers h2").text).to eq(I18n.t("relationships.tabs.followers"))
    expect(parse_html.css("#relationships-grid form")).to be_empty
  end

  it "includes the received book-friend requests anchor in the relationship hub" do
    sign_in viewer

    get account_relationships_path, params: { tab: "received_book_friend_requests" }

    expect(parse_html.at_css("#received-book-friend-requests")).not_to be_nil
  end

  it "shows clear relationship action labels" do
    sign_in viewer

    {
      "received_book_friend_requests" => %w[accept_book_friend reject_book_friend_request],
      "sent_book_friend_requests" => %w[cancel_book_friend_request],
      "book_friends" => %w[remove_book_friend],
      "following_users" => %w[unfollow]
    }.each do |tab, actions|
      get account_relationships_path, params: { tab: tab }
      actions.each { |action| expect(parse_html.at_css("#relationships-grid").text).to include(I18n.t("users.actions.#{action}")) }
    end
  end

  it "does not show other users' requests or relationships" do
    sign_in viewer

    RelationshipsQuery::TABS.each do |tab|
      get account_relationships_path, params: { tab: tab }
      expect(response.body).not_to include("Hidden Requester")
      expect(response.body).not_to include("Hidden Addressee")
      expect(response.body).not_to include("Hidden Book Friend")
    end
  end

  it "counts all five tabs but renders only the selected relationship" do
    sign_in viewer
    users_by_tab = {
      "book_friends" => book_friend,
      "received_book_friend_requests" => received_requester,
      "sent_book_friend_requests" => sent_addressee,
      "following_users" => followee,
      "followers" => follower
    }

    users_by_tab.each do |tab, selected_user|
      get account_relationships_path, params: { tab: tab }
      expect(parse_html.css("#relationships-grid article").size).to eq(1)
      expect(parse_html.at_css("#relationships-grid a")["href"]).to eq(user_path(selected_user))
      users_by_tab.each do |key, user|
        expect(parse_html.at_css("#relationships-count-#{key}").text).to eq("1")
        expect(parse_html.at_css("#relationships-grid").text).not_to include(user.name) unless key == tab
      end
    end
  end

  it "normalizes unknown or malformed tabs and pages and does not expose extra card information" do
    book_friend.update!(handle: "public_friend")
    sign_in viewer

    [ { tab: "unknown", page: "wrong" }, { tab: [ "followers" ], page: [ "2" ] },
      { tab: { invalid: "followers" }, page: "-1", q: { invalid: "text" } }, { page: "0" } ].each do |params|
      get account_relationships_path, params: params
      expect(response).to have_http_status(:ok)
      expect(parse_html.at_css("a[aria-current='page']")["id"]).to eq("relationships-tab-book_friends")
      expect(parse_html.at_css("#relationships-grid").text).to include(book_friend.name, "@public_friend")
      expect(parse_html.css("#relationships-grid article p").map(&:text)).to eq([ book_friend.name, "@public_friend" ])
      expect(parse_html.at_css("#relationships-grid article a")["title"]).to eq(book_friend.name)
      expect(parse_html.at_css("#relationships-grid input[name='page']")["value"]).to eq("1")
    end
  end

  it "searches only names within the current tab, escapes wildcard characters, and keeps total tab counts" do
    received_requester.update!(name: "Literal%_ Reader", handle: "needle_handle")
    another = User.create!(name: "Literal other", handle: "needlexhandle", email: "needle-other@example.com", password: "password123!")
    another.requested_book_friendships.create!(addressee: viewer)
    sign_in viewer

    [ "literal%_", "READER", "%", "_" ].each do |query|
      get account_relationships_path, params: { tab: "received_book_friend_requests", q: query }
      expect(parse_html.css("#relationships-grid article").size).to eq(1)
      expect(parse_html.at_css("#relationships-grid a")["href"]).to eq(user_path(received_requester))
      expect(parse_html.at_css("#relationships-count-received_book_friend_requests").text).to eq("2")
      expect(parse_html.at_css("#relationships-panel label[for='q']").text).to eq(I18n.t("relationships.search.label"))
      expect(parse_html.at_css("#relationships-panel input[name='q']")["placeholder"]).to eq(I18n.t("relationships.search.placeholder"))
      expect(parse_html.at_css("form[method='get'] input[name='page']")).to be_nil
      links = parse_html.css("nav[aria-label] a[href^='/account/relationships']")
      expect(links.size).to eq(5)
      links.each do |link|
        filters = Rack::Utils.parse_query(URI.parse(link["href"]).query)
        expect(filters["q"]).to eq(query)
        expect(filters["page"]).to be_nil
      end
    end

    get account_relationships_path, params: { tab: "received_book_friend_requests", q: "needle_handle" }
    expect(parse_html.at_css("#relationships-grid")).to be_nil
    expect(parse_html.at_css("#relationships-panel").text).to include(I18n.t("relationships.search.empty"))
    expect(parse_html.at_css("#relationships-count-received_book_friend_requests").text).to eq("2")

    get account_relationships_path, params: { tab: "sent_book_friend_requests", q: "Literal%_" }
    expect(parse_html.at_css("#relationships-grid")).to be_nil
    expect(parse_html.at_css("#relationships-panel").text).to include(I18n.t("relationships.search.empty"))
    expect(parse_html.at_css("#relationships-count-sent_book_friend_requests").text).to eq("1")
  end

  %w[book_friends following_users followers].each do |tab|
    it "paginates #{tab} by 24 users in name and id order" do
      users = 25.times.map do |index|
        user = User.create!(name: "Paged reader", email: "#{tab}-#{index}@example.com", password: "password123!")
        case tab
        when "book_friends"
          requester, addressee = index.even? ? [ viewer, user ] : [ user, viewer ]
          BookFriendship.create!(requester: requester, addressee: addressee, status: :accepted)
        when "following_users"
          viewer.active_follows.create!(followee: user)
        when "followers"
          user.active_follows.create!(followee: viewer)
        end
        user
      end
      existing = { "book_friends" => book_friend, "following_users" => followee, "followers" => follower }.fetch(tab)
      expected = [ existing ] + users
      sign_in viewer

      get account_relationships_path, params: { tab: tab }
      expect(parse_html.css("#relationships-grid article a").map { |link| link["href"] }).to eq(expected.first(24).map { |user| user_path(user) })
      expect(parse_html.at_css("#relationships-count-#{tab}").text).to eq("26")
      next_link = parse_html.css("#relationships-panel nav a").find { |link| link.text == I18n.t("pagination.next") }
      expect(Rack::Utils.parse_query(URI.parse(next_link["href"]).query)).to include("tab" => tab, "page" => "2")
      get next_link["href"]
      expect(parse_html.css("#relationships-grid article a").map { |link| link["href"] }).to eq(expected.drop(24).map { |user| user_path(user) })
    end
  end

  %w[received_book_friend_requests sent_book_friend_requests].each do |tab|
    it "paginates #{tab} by 24 requests in newest first and id order" do
      users = 25.times.map do |index|
        user = User.create!(name: "New request #{index}", email: "#{tab}-#{index}@example.com", password: "password123!")
        requester, addressee = tab == "received_book_friend_requests" ? [ user, viewer ] : [ viewer, user ]
        BookFriendship.create!(requester: requester, addressee: addressee, created_at: 1.day.from_now.beginning_of_day)
        user
      end
      existing = tab == "received_book_friend_requests" ? received_requester : sent_addressee
      expected = users.reverse + [ existing ]
      sign_in viewer

      get account_relationships_path, params: { tab: tab }
      expect(parse_html.css("#relationships-grid article a").map { |link| link["href"] }).to eq(expected.first(24).map { |user| user_path(user) })
      get account_relationships_path, params: { tab: tab, page: "999" }
      expect(parse_html.css("#relationships-grid article a").map { |link| link["href"] }).to eq(expected.drop(24).map { |user| user_path(user) })
      expect(parse_html.at_css("#relationships-grid input[name='page']")["value"]).to eq("2")
    end
  end

  it "keeps the selected tab, search, and page after acceptance and refreshes counts and pagination links" do
    26.times do |index|
      user = User.create!(name: "Received page #{index}", email: "received-page-#{index}@example.com", password: "password123!")
      BookFriendship.create!(requester: user, addressee: viewer, created_at: 1.day.from_now.beginning_of_day)
    end
    sign_in viewer

    patch user_book_friendship_path(received_requester),
          params: { return_to: "relationships", tab: "received_book_friend_requests", q: "Received", page: 2 },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(parse_html.css("turbo-stream[action='replace']").map { |stream| stream["target"] }).to eq([ "relationships-panel" ])
    expect(parse_html.at_css("#relationships-count-received_book_friend_requests").text).to eq("26")
    expect(parse_html.at_css("#relationships-count-book_friends").text).to eq("2")
    expect(parse_html.css("#relationships-grid article").size).to eq(2)
    expect(parse_html.at_css("#relationships-panel input[name='q']")["value"]).to eq("Received")
    parse_html.css("#relationships-grid form").each do |form|
      expect(form.at_css("input[name='tab']")["value"]).to eq("received_book_friend_requests")
      expect(form.at_css("input[name='q']")["value"]).to eq("Received")
      expect(form.at_css("input[name='page']")["value"]).to eq("2")
    end
    previous_link = parse_html.css("#relationships-panel nav a").find { |link| link.text == I18n.t("pagination.previous") }
    expect(previous_link["href"]).to eq(account_relationships_path(tab: "received_book_friend_requests", q: "Received", page: 1))
  end

  [ :html, :turbo_stream ].each do |format|
    it "redirects to a valid page with the current search after the last item disappears using #{format}" do
      24.times do |index|
        user = User.create!(name: "Received page #{index}", email: "last-page-#{index}@example.com", password: "password123!")
        BookFriendship.create!(requester: user, addressee: viewer, created_at: 1.day.from_now.beginning_of_day)
      end
      sign_in viewer
      headers = format == :turbo_stream ? { "Accept" => "text/vnd.turbo-stream.html" } : {}

      patch user_book_friendship_path(received_requester),
            params: { return_to: "relationships", tab: "received_book_friend_requests", q: "Received", page: 2 },
            headers: headers

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(account_relationships_path(tab: "received_book_friend_requests", q: "Received", page: 1))
      follow_redirect!(headers: headers)
      expect(response.media_type).to eq("text/html")
      expect(parse_html.css("#relationships-grid article").size).to eq(24)
      expect(parse_html.at_css("#relationships-count-received_book_friend_requests").text).to eq("24")
      expect(parse_html.at_css("#relationships-count-book_friends").text).to eq("2")
      expect(parse_html.at_css("#relationships-panel input[name='q']")["value"]).to eq("Received")
      expect(parse_html.at_css("#relationships-grid input[name='page']")["value"]).to eq("1")
    end
  end
end
