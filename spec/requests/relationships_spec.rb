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

  def relationship_nav_link
    parse_html.css("a").find do |link|
      link.text.include?(I18n.t("relationships.nav"))
    end
  end

  it "redirects guests to sign in" do
    get relationships_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not show relationship notification UI to guests" do
    get new_user_session_path

    expect(response.body).not_to include("relationship-notification-badge")
    expect(response.body).not_to include(%(href="/relationships#received-book-friend-requests"))
  end

  it "allows signed-in users to open the relationship hub" do
    sign_in viewer

    get relationships_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("relationships.title"))
  end

  it "shows the current user's pending received book-friend request count in the navigation" do
    sign_in viewer

    get root_path

    badge = parse_html.at_css("#relationship-notification-badge")

    expect(badge).not_to be_nil
    expect(badge.text.strip).to eq("1")
  end

  it "links the relationships navigation to the received requests anchor when pending requests exist" do
    sign_in viewer

    get root_path

    expect(relationship_nav_link&.[]("href")).to eq("/relationships#received-book-friend-requests")
  end

  it "does not include other users' pending requests in the notification count" do
    sign_in viewer

    get root_path

    badge = parse_html.at_css("#relationship-notification-badge")

    expect(badge.text.strip).to eq("1")
    expect(badge.text.strip).not_to eq("2")
  end

  it "does not show a notification badge when the current user has no pending received requests" do
    BookFriendship.where(addressee: viewer, status: :pending).delete_all
    sign_in viewer

    get root_path

    expect(parse_html.at_css("#relationship-notification-badge")).to be_nil
    expect(relationship_nav_link&.[]("href")).to eq("/relationships")
  end

  it "shows received book-friend requests to the addressee" do
    sign_in viewer

    get relationships_path

    expect(response.body).to include("Received Requester")
  end

  it "shows sent book-friend requests to the requester" do
    sign_in viewer

    get relationships_path

    expect(response.body).to include("Sent Addressee")
  end

  it "shows accepted book friends" do
    sign_in viewer

    get relationships_path

    expect(response.body).to include("Book Friend")
  end

  it "shows users the viewer follows" do
    sign_in viewer

    get relationships_path

    expect(response.body).to include("Followee")
  end

  it "shows users following the viewer" do
    sign_in viewer

    get relationships_path

    expect(response.body).to include("Follower")
  end

  it "includes the received book-friend requests anchor in the relationship hub" do
    sign_in viewer

    get relationships_path

    expect(parse_html.at_css("#received-book-friend-requests")).not_to be_nil
  end

  it "does not show other users' requests or relationships" do
    sign_in viewer

    get relationships_path

    expect(response.body).not_to include("Hidden Requester")
    expect(response.body).not_to include("Hidden Addressee")
    expect(response.body).not_to include("Hidden Book Friend")
  end
end
