require "rails_helper"

RSpec.describe "Users", type: :request do
  let!(:viewer) { User.create!(name: "Viewer", email: "viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:profile_user) { User.create!(name: "Profile User", email: "profile@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:other_user) { User.create!(name: "Other", email: "other@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "프로필 책", authors_text: "저자") }
  let!(:profile_entry) { profile_user.bookshelf_entries.create!(book:, status: :reading) }
  let!(:profile_jjaek) { profile_user.jjaeks.create!(book:, content: "Profile Jjaek") }
  let!(:other_jjaek) { other_user.jjaeks.create!(book:, content: "Other private", visibility: :private_jjaek) }

  describe "GET /users/:id" do
    it "redirects guests to sign in" do
      get user_path(profile_user)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the profile user's shelf and public jjaeks" do
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include("프로필 책")
      expect(response.body).to include("Profile Jjaek")
      expect(response.body).not_to include("Other private")
    end
  end
end
