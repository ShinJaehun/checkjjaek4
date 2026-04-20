require "rails_helper"

RSpec.describe "Jjaeks", type: :request do
  let!(:user) { User.create!(name: "Writer", email: "writer@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:followee) { User.create!(name: "Followee", email: "followee@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:stranger) { User.create!(name: "Stranger", email: "stranger@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "짹의 책", authors_text: "저자") }
  let!(:own_jjaek) { user.jjaeks.create!(book:, content: "My note") }
  let!(:followee_jjaek) { followee.jjaeks.create!(book:, content: "Followee note") }
  let!(:stranger_jjaek) { stranger.jjaeks.create!(book:, content: "Stranger note") }

  before do
    user.active_follows.create!(followee:)
  end

  describe "GET /" do
    it "redirects guests to sign in" do
      get root_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the signed-in user's feed and hides unrelated jjaeks" do
      sign_in user

      get root_path

      expect(response.body).to include("My note")
      expect(response.body).to include("Followee note")
      expect(response.body).not_to include("Stranger note")
    end
  end

  describe "POST /jjaeks" do
    it "creates a jjaek for the current user" do
      sign_in user

      expect {
        post jjaeks_path, params: { jjaek: { book_id: book.id, content: "Fresh update", visibility: :public_jjaek } }
      }.to change(user.jjaeks, :count).by(1)

      expect(response).to redirect_to(jjaek_path(Jjaek.order(:id).last))
    end
  end

  describe "PATCH /jjaeks/:id" do
    it "updates the current user's jjaek" do
      sign_in user

      patch jjaek_path(own_jjaek), params: { jjaek: { content: "Updated note" } }

      expect(response).to redirect_to(jjaek_path(own_jjaek))
      expect(own_jjaek.reload.content).to eq("Updated note")
    end
  end

  describe "DELETE /jjaeks/:id" do
    it "deletes the current user's jjaek" do
      sign_in user

      expect {
        delete jjaek_path(own_jjaek)
      }.to change(Jjaek, :count).by(-1)

      expect(response).to redirect_to(root_path)
    end
  end
end
