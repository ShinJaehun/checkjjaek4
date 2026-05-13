require "rails_helper"

RSpec.describe "BookFriendships", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader-book-friend@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:other_user) { User.create!(name: "Other", email: "other-book-friend@example.com", password: "password123!", password_confirmation: "password123!") }

  it "lets a signed-in user request book friendship" do
    sign_in user

    expect {
      post user_book_friendship_path(other_user)
    }.to change(BookFriendship, :count).by(1)
  end

  it "creates a notification for the addressee when requesting book friendship" do
    sign_in user

    expect {
      post user_book_friendship_path(other_user)
    }.to change(Notification, :count).by(1)

    notification = Notification.last
    expect(notification).to be_book_friendship_requested
    expect(notification.recipient).to eq(other_user)
    expect(notification.actor).to eq(user)
    expect(notification.notifiable).to eq(BookFriendship.last)
  end

  it "lets the addressee accept the request" do
    BookFriendship.create!(requester: user, addressee: other_user)
    sign_in other_user

    patch user_book_friendship_path(user)

    expect(BookFriendship.last).to be_accepted
  end

  it "returns to the relationship hub when return_to is relationships" do
    BookFriendship.create!(requester: user, addressee: other_user)
    sign_in other_user

    patch user_book_friendship_path(user), params: { return_to: "relationships" }

    expect(response).to redirect_to(relationships_path)
  end

  it "updates received requests and book friends when accepting from the relationship hub with Turbo" do
    friendship = BookFriendship.create!(requester: user, addressee: other_user)
    sign_in other_user

    patch user_book_friendship_path(user),
          params: { return_to: "relationships" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(friendship.reload).to be_accepted
    expect(response.body).to include(%(action="replace" target="received-book-friend-requests"))
    expect(response.body).to include(%(action="replace" target="book-friends"))
    expect(response.body).to include(%(action="update" target="flash-messages"))
    expect(response.body).to include(I18n.t("relationships.empty.received_book_friend_requests"))
    expect(response.body).to include(user.name)
  end

  it "falls back to the user profile for an unknown return_to value" do
    BookFriendship.create!(requester: user, addressee: other_user)
    sign_in other_user

    patch user_book_friendship_path(user), params: { return_to: "https://example.com" }

    expect(response).to redirect_to(user_path(user))
  end

  it "shows a cancel notice when the requester deletes a pending request" do
    BookFriendship.create!(requester: user, addressee: other_user)
    sign_in user

    delete user_book_friendship_path(other_user), params: { return_to: "relationships" }

    expect(response).to redirect_to(relationships_path)
    expect(flash[:notice]).to eq(I18n.t("book_friendships.notices.cancelled"))
  end

  it "updates the sent book friend requests section when cancelling from the relationship hub with Turbo" do
    BookFriendship.create!(requester: user, addressee: other_user)
    sign_in user

    expect {
      delete user_book_friendship_path(other_user),
             params: { return_to: "relationships" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(BookFriendship, :count).by(-1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="replace" target="sent-book-friend-requests"))
    expect(response.body).to include(%(action="update" target="flash-messages"))
    expect(response.body).to include(I18n.t("relationships.empty.sent_book_friend_requests"))
  end

  it "shows a reject notice when the addressee deletes a pending request" do
    BookFriendship.create!(requester: user, addressee: other_user)
    sign_in other_user

    delete user_book_friendship_path(user), params: { return_to: "relationships" }

    expect(response).to redirect_to(relationships_path)
    expect(flash[:notice]).to eq(I18n.t("book_friendships.notices.rejected"))
  end

  it "updates the received book friend requests section when rejecting from the relationship hub with Turbo" do
    BookFriendship.create!(requester: user, addressee: other_user)
    sign_in other_user

    expect {
      delete user_book_friendship_path(user),
             params: { return_to: "relationships" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(BookFriendship, :count).by(-1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="replace" target="received-book-friend-requests"))
    expect(response.body).to include(%(action="update" target="flash-messages"))
    expect(response.body).to include(I18n.t("relationships.empty.received_book_friend_requests"))
  end

  it "shows a remove notice when deleting an accepted book friendship" do
    BookFriendship.create!(requester: user, addressee: other_user, status: :accepted)
    sign_in user

    delete user_book_friendship_path(other_user), params: { return_to: "relationships" }

    expect(response).to redirect_to(relationships_path)
    expect(flash[:notice]).to eq(I18n.t("book_friendships.notices.removed"))
  end
end
