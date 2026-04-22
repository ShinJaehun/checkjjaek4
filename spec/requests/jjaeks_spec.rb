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

  describe "POST /jjaeks" do
    it "creates a general jjaek without a book" do
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            content: "GENERAL_JJAEK_BODY",
            visibility: :public_jjaek
          }
        }
      }.to change(Jjaek, :count).by(1)

      created_jjaek = Jjaek.last
      expect(created_jjaek.book).to be_nil
      expect(response).to redirect_to(jjaek_path(created_jjaek))
    end

    it "rerenders the home form when a general jjaek is invalid" do
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            content: "",
            visibility: :public_jjaek
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("home.new_jjaek_title"))
      expect(response.body).to include("textarea")
      expect(response.body).to include('name="jjaek[content]"')
    end

    it "creates a book-linked jjaek from a shelf context" do
      viewer.bookshelf_entries.create!(book:)
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            book_id: book.id,
            content: "BOOK_JJAEK_BODY",
            visibility: :public_jjaek
          }
        }
      }.to change(Jjaek, :count).by(1)

      created_jjaek = Jjaek.last
      expect(created_jjaek.book).to eq(book)
      expect(response).to redirect_to(jjaek_path(created_jjaek))
    end
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
