require "rails_helper"

RSpec.describe "Posts", type: :request do
  let!(:user) { User.create!(name: "Writer", email: "writer@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:followee) { User.create!(name: "Followee", email: "followee@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:stranger) { User.create!(name: "Stranger", email: "stranger@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:own_post) { user.posts.create!(content: "My note") }
  let!(:followee_post) { followee.posts.create!(content: "Followee note") }
  let!(:stranger_post) { stranger.posts.create!(content: "Stranger note") }

  before do
    user.active_follows.create!(followee: followee)
  end

  describe "GET /" do
    it "redirects guests to sign in" do
      get root_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the signed-in user's feed and hides unrelated posts" do
      sign_in user

      get root_path

      expect(response.body).to include("My note")
      expect(response.body).to include("Followee note")
      expect(response.body).not_to include("Stranger note")
    end
  end

  describe "POST /posts" do
    it "creates a post for the current user" do
      sign_in user

      expect {
        post posts_path, params: { post: { content: "Fresh update" } }
      }.to change(user.posts, :count).by(1)

      expect(response).to redirect_to(root_path)
    end
  end
end
