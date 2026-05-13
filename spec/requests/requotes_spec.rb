require "rails_helper"

RSpec.describe "Requotes", type: :request do
  let(:viewer) { User.create!(name: "Reader", email: "requote-request-reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:original_author) { User.create!(name: "Original", email: "requote-request-original@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "Requote list book", authors_text: "Author") }
  let(:friendship) { BookFriendship.create!(requester: viewer, addressee: original_author, status: :accepted) }
  let(:original) { original_author.jjaeks.create!(book:, content: "REQUEST_ORIGINAL_BOOK_FRIENDS_SOURCE", visibility: :book_friends) }
  let(:viewer_requote) { viewer.jjaeks.create!(book:, content: "REQUEST_VIEWER_REQUOTE_BODY", quoted_jjaek: original, visibility: :private_jjaek) }

  before do
    friendship
  end

  describe "GET /jjaeks/:jjaek_id/requotes" do
    it "shows only requotes visible to the viewer" do
      visible_book_friends_requote = original_author.jjaeks.create!(
        content: "VISIBLE_BOOK_FRIENDS_REQUOTE",
        quoted_jjaek: original,
        visibility: :book_friends
      )

      hidden_requoter = User.create!(
        name: "Hidden Requoter",
        email: "hidden-requote-list@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      )

      BookFriendship.create!(
        requester: hidden_requoter,
        addressee: original_author,
        status: :accepted
      )

      hidden_requoter.jjaeks.create!(
        content: "HIDDEN_REQUOTE_IN_LIST",
        quoted_jjaek: original,
        visibility: :book_friends
      )

      viewer_requote
      sign_in viewer

      get jjaek_requotes_path(original)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("requotes.index.title"))
      expect(response.body).to include(original.content)
      expect(response.body).to include(visible_book_friends_requote.content)
      expect(response.body).to include(viewer_requote.content)
      expect(response.body).not_to include("HIDDEN_REQUOTE_IN_LIST")
    end

    it "replaces the detail requotes panel on turbo stream index" do
      visible_book_friends_requote = original_author.jjaeks.create!(
        content: "VISIBLE_TURBO_BOOK_FRIENDS_REQUOTE",
        quoted_jjaek: original,
        visibility: :book_friends
      )

      hidden_requoter = User.create!(
        name: "Hidden Requoter",
        email: "hidden-turbo-requote-list@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      )

      BookFriendship.create!(
        requester: hidden_requoter,
        addressee: original_author,
        status: :accepted
      )

      hidden_requoter.jjaeks.create!(
        content: "HIDDEN_TURBO_REQUOTE_IN_LIST",
        quoted_jjaek: original,
        visibility: :book_friends
      )

      viewer_requote
      sign_in viewer

      get jjaek_requotes_path(original), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="requotes_panel_jjaek_#{original.id}"))
      expect(response.body).to include(%(id="requotes_panel_jjaek_#{original.id}"))
      expect(response.body).to include(visible_book_friends_requote.content)
      expect(response.body).to include(viewer_requote.content)
      expect(response.body).not_to include("HIDDEN_TURBO_REQUOTE_IN_LIST")
      expect(response.body).not_to include(I18n.t("requotes.index.description"))
    end

    it "does not allow requote list access for a private original" do
      private_original = viewer.jjaeks.create!(content: "PRIVATE_REQUOTE_LIST_SOURCE", visibility: :private_jjaek)
      sign_in viewer

      get jjaek_requotes_path(private_original)

      expect(response).to redirect_to(root_path)
    end

    it "does not allow requote list access for a requote" do
      sign_in viewer
      viewer_requote

      get jjaek_requotes_path(viewer_requote)

      expect(response).to redirect_to(root_path)
    end
  end
end
