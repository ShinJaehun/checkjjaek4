require "rails_helper"

RSpec.describe "Users", type: :request do
  let!(:viewer) { User.create!(name: "Viewer", email: "viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:profile_user) { User.create!(name: "Profile User", email: "profile@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:other_user) { User.create!(name: "Other", email: "other@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "프로필 책", authors_text: "저자") }
  let!(:shelf_book) { Book.create!(title: "프로필 서재 전용 책", authors_text: "저자") }
  let!(:profile_entry) { profile_user.bookshelf_entries.create!(book: shelf_book, status: :reading) }
  let!(:profile_jjaek) { profile_user.jjaeks.create!(book:, content: "Profile Jjaek") }
  let!(:profile_friend_jjaek) { profile_user.jjaeks.create!(content: "Book friend profile Jjaek", visibility: :book_friends) }
  let!(:profile_private_jjaek) { profile_user.jjaeks.create!(content: "Private profile Jjaek", visibility: :private_jjaek) }
  let!(:other_jjaek) { other_user.jjaeks.create!(book:, content: "Other private", visibility: :private_jjaek) }

  describe "GET /users/:id" do
    it "redirects guests to sign in" do
      get user_path(profile_user)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows public jjaeks but not shelf entries or book-friend jjaeks to unrelated users" do
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include("Profile Jjaek")
      expect(response.body).not_to include("프로필 서재 전용 책")
      expect(response.body).not_to include("Book friend profile Jjaek")
      expect(response.body).not_to include("Private profile Jjaek")
      expect(response.body).not_to include("Other private")
      expect(response.body).not_to include(I18n.t("users.profile.new_jjaek_title"))
    end

    it "does not grant shelf or book-friend visibility to follow-only users" do
      viewer.active_follows.create!(followee: profile_user)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include("Profile Jjaek")
      expect(response.body).not_to include("프로필 서재 전용 책")
      expect(response.body).not_to include("Book friend profile Jjaek")
      expect(response.body).not_to include(I18n.t("users.profile.new_jjaek_title"))
    end

    it "shows shelf entries, book-friend jjaeks, and a profile-context form to accepted book friends" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include("프로필 서재 전용 책")
      expect(response.body).to include("Profile Jjaek")
      expect(response.body).to include("Book friend profile Jjaek")
      expect(response.body).not_to include("Private profile Jjaek")
      expect(response.body).to include(I18n.t("users.profile.new_jjaek_title"))
      expect(response.body).to include('name="context_user_id"')
      expect(response.body).to include(I18n.t("jjaeks.visibility.book_friends"))
    end

    it "shows the user's own shelf, private jjaeks, and profile-context form" do
      own_book = Book.create!(title: "내 책", authors_text: "저자")
      viewer.bookshelf_entries.create!(book: own_book)
      viewer.jjaeks.create!(content: "내 비공개 짹", visibility: :private_jjaek)
      sign_in viewer

      get user_path(viewer)

      expect(response.body).to include("내 책")
      expect(response.body).to include("내 비공개 짹")
      expect(response.body).to include(I18n.t("users.profile.new_jjaek_title"))
      expect(response.body).to include(I18n.t("jjaeks.visibility.private_jjaek"))
    end

    it "rerenders the profile-context form when a profile-context jjaek is invalid" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          context_user_id: profile_user.id,
          jjaek: {
            content: "",
            visibility: :book_friends
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("users.profile.new_jjaek_title"))
      expect(response.body).to include('name="context_user_id"')
    end
  end
end
