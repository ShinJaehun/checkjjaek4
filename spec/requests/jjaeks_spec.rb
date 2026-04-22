require "rails_helper"

RSpec.describe "Jjaeks", type: :request do
  let(:viewer) { User.create!(name: "Reader", email: "jjaek-request-reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:original_author) { User.create!(name: "Original", email: "jjaek-request-original@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "ReJjaek request book", authors_text: "Author") }
  let(:friendship) { BookFriendship.create!(requester: viewer, addressee: original_author, status: :accepted) }
  let(:original) { original_author.jjaeks.create!(book:, content: "REQUEST_ORIGINAL_BOOK_FRIENDS_SOURCE", visibility: :book_friends) }
  let(:requote) { viewer.jjaeks.create!(book:, content: "REQUEST_VIEWER_REQUOTE_BODY", quoted_jjaek: original, visibility: :private_jjaek) }

  before do
    friendship
  end

  describe "GET /jjaeks/:id" do
    it "blocks a user's own requote when the original is no longer visible to them" do
      sign_in viewer
      requote
      friendship.destroy!

      get jjaek_path(requote)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /" do
    it "hides a requote from the home feed when the original is no longer visible to the viewer" do
      sign_in viewer
      requote
      friendship.destroy!

      get root_path

      expect(response.body).not_to include("REQUEST_VIEWER_REQUOTE_BODY")
    end

    it "shows a requote in the home feed when the original is still visible to the viewer" do
      sign_in viewer
      requote

      get root_path

      expect(response.body).to include("REQUEST_VIEWER_REQUOTE_BODY")
    end
  end
end
