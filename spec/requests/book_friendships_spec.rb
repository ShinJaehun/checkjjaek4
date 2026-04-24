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

  it "falls back to the user profile for an unknown return_to value" do
    BookFriendship.create!(requester: user, addressee: other_user)
    sign_in other_user

    patch user_book_friendship_path(user), params: { return_to: "https://example.com" }

    expect(response).to redirect_to(user_path(user))
  end
end
