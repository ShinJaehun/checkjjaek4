require "rails_helper"

RSpec.describe "Users", type: :request do
  let!(:viewer) { User.create!(name: "Viewer", email: "viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:profile_user) { User.create!(name: "Profile User", email: "profile@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:other_user) { User.create!(name: "Other", email: "other@example.com", password: "password123!", password_confirmation: "password123!") }

  let!(:profile_post) { profile_user.posts.create!(content: "Profile post") }
  let!(:other_post) { other_user.posts.create!(content: "Other post") }

  describe "GET /users/:id" do
    it "redirects guests to sign in" do
      get user_path(profile_user)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the profile user's public posts even when the viewer does not follow them" do
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include("Profile post")
      expect(response.body).not_to include("Other post")
    end

    it "shows the profile user's public posts when the viewer follows them" do
      sign_in viewer
      viewer.active_follows.create!(followee: profile_user)

      get user_path(profile_user)

      expect(response.body).to include("Profile post")
    end
  end
end
