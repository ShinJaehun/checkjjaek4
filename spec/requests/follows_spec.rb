require "rails_helper"

RSpec.describe "Follows", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader3@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:other_user) { User.create!(name: "Other", email: "other@example.com", password: "password123!", password_confirmation: "password123!") }

  it "lets a signed-in user follow another user" do
    sign_in user

    expect {
      post user_follow_path(other_user)
    }.to change(Follow, :count).by(1)
  end

  it "redirects guests to sign in when following a user" do
    post user_follow_path(other_user)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not allow a user to follow themselves" do
    sign_in user

    expect {
      post user_follow_path(user)
    }.not_to change(Follow, :count)

    expect(response).to redirect_to(root_path)
  end

  it "lets a signed-in user unfollow a followed user" do
    sign_in user
    user.active_follows.create!(followee: other_user)

    expect {
      delete user_follow_path(other_user)
    }.to change(Follow, :count).by(-1)
  end

  it "returns to the relationship hub when return_to is relationships" do
    sign_in user
    user.active_follows.create!(followee: other_user)

    delete user_follow_path(other_user), params: { return_to: "relationships" }

    expect(response).to redirect_to(relationships_path)
  end

  it "redirects back with an alert when the follow does not exist" do
    sign_in user

    delete user_follow_path(other_user)

    expect(response).to redirect_to(user_path(other_user))
    expect(flash[:alert]).to eq("팔로우 관계를 찾을 수 없습니다.")
  end

  it "falls back to the user profile for an unknown return_to value" do
    sign_in user
    user.active_follows.create!(followee: other_user)

    delete user_follow_path(other_user), params: { return_to: "https://example.com" }

    expect(response).to redirect_to(user_path(other_user))
  end
end
