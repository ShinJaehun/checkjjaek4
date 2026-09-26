require "rails_helper"

RSpec.describe "Interaction preferences on profiles", type: :request do
  let!(:viewer) { User.create!(name: "Viewer", email: "preferences-profile-viewer@example.com", password: "password123!") }
  let!(:target) { User.create!(name: "Target", email: "preferences-profile-target@example.com", password: "password123!") }

  before do
    sign_in viewer
    target.update!(allows_new_followers: false, accepts_book_friend_requests: false)
  end

  it "hides only the two new relationship actions when there is no relationship" do
    get user_path(target)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("form[action='#{user_follow_path(target)}']")).to be_nil
    expect(page.at_css("form[action='#{user_book_friendship_path(target)}']")).to be_nil
  end

  it "keeps unfollow and accepted friendship removal visible" do
    viewer.active_follows.create!(followee: target)
    BookFriendship.create!(requester: viewer, addressee: target, status: :accepted)

    get user_path(target)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("form[action='#{user_follow_path(target)}']").text).to include(I18n.t("users.actions.unfollow"))
    expect(page.at_css("form[action='#{user_book_friendship_path(target)}']").text).to include(I18n.t("users.actions.remove_book_friend"))
  end

  it "keeps a sent pending request cancellation visible" do
    BookFriendship.create!(requester: viewer, addressee: target)

    get user_path(target)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("form[action='#{user_book_friendship_path(target)}']").text).to include(I18n.t("users.actions.cancel_book_friend_request"))
  end

  it "keeps a received pending request acceptance visible" do
    BookFriendship.create!(requester: target, addressee: viewer)

    get user_path(target)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("form[action='#{user_book_friendship_path(target)}']").text).to include(I18n.t("users.actions.accept_book_friend"))
  end
end
