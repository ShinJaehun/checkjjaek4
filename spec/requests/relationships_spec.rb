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
    expect(response.body).not_to include(%(href="/account/relationships#received-book-friend-requests"))
  end

  it "allows signed-in users to open the relationship hub" do
    sign_in viewer

    get account_relationships_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("relationships.title"))
    expect(response.body).to include(I18n.t("relationships.description"))
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

    get account_relationships_path

    expect(response.body).to include("Received Requester")
  end

  it "shows sent book-friend requests to the requester" do
    sign_in viewer

    get account_relationships_path

    expect(response.body).to include("Sent Addressee")
  end

  it "shows accepted book friends" do
    sign_in viewer

    get account_relationships_path

    expect(response.body).to include("Book Friend")
  end

  it "shows users the viewer follows" do
    sign_in viewer

    get account_relationships_path

    expect(response.body).to include("Followee")
  end

  it "shows users following the viewer" do
    sign_in viewer

    get account_relationships_path

    expect(response.body).to include("Follower")
  end

  it "includes the received book-friend requests anchor in the relationship hub" do
    sign_in viewer

    get account_relationships_path

    expect(parse_html.at_css("#received-book-friend-requests")).not_to be_nil
  end

  it "shows clear relationship action labels" do
    sign_in viewer

    get account_relationships_path

    expect(response.body).to include(I18n.t("users.actions.accept_book_friend"))
    expect(response.body).to include(I18n.t("users.actions.reject_book_friend_request"))
    expect(response.body).to include(I18n.t("users.actions.cancel_book_friend_request"))
    expect(response.body).to include(I18n.t("users.actions.remove_book_friend"))
    expect(response.body).to include(I18n.t("users.actions.unfollow"))
  end

  it "does not show other users' requests or relationships" do
    sign_in viewer

    get account_relationships_path

    expect(response.body).not_to include("Hidden Requester")
    expect(response.body).not_to include("Hidden Addressee")
    expect(response.body).not_to include("Hidden Book Friend")
  end
end
