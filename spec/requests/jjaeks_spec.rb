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

      expect(response).to have_http_status(:unprocessable_content)
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

    it "does not create a book-linked jjaek without a shelf entry" do
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            book_id: book.id,
            content: "NO_SHELF_DIRECT_BOOK_JJAEK",
            visibility: :public_jjaek
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to redirect_to(root_path)
    end

    it "creates a requote from a visible original" do
      sign_in viewer
      original

      expect {
        post jjaeks_path, params: {
          jjaek: {
            quoted_jjaek_id: original.id,
            content: "REQUEST_NEW_REQUOTE_BODY",
            visibility: :private_jjaek
          }
        }
      }.to change(Jjaek, :count).by(1)

      created_jjaek = Jjaek.last
      expect(created_jjaek.quoted_jjaek).to eq(original)
      expect(created_jjaek.book).to be_nil
      expect(response).to redirect_to(jjaek_path(created_jjaek))
    end

    it "rerenders the new requote form when a requote is invalid" do
      sign_in viewer
      original

      expect {
        post jjaeks_path, params: {
          jjaek: {
            quoted_jjaek_id: original.id,
            content: "",
            visibility: :private_jjaek
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("jjaeks.new.requote_title"))
      expect(response.body).to include("REQUEST_ORIGINAL_BOOK_FRIENDS_SOURCE")
    end

    it "shows a domain error when a requote visibility is broader than the original" do
      sign_in viewer
      original

      expect {
        post jjaeks_path, params: {
          jjaek: {
            quoted_jjaek_id: original.id,
            content: "REQUEST_TOO_PUBLIC_REQUOTE_BODY",
            visibility: :public_jjaek
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("activerecord.errors.models.jjaek.attributes.visibility.cannot_exceed_quoted_visibility"))
    end
  end

  describe "GET /jjaeks/:id" do
    it "shows a requote entry on a visible jjaek detail page" do
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include(new_jjaek_path(quoted_jjaek_id: original.id))
    end

    it "shows the requote context label on the detail page" do
      sign_in viewer

      get jjaek_path(requote)

      expect(response.body).to include(viewer.name)
      expect(response.body).to include(user_path(viewer))
      expect(response.body).to include(original_author.name)
      expect(response.body).to include(user_path(original_author))
      expect(response.body).to include("님의 짹을 다시짹")
    end

    it "does not show a requote entry for a private jjaek" do
      private_jjaek = viewer.jjaeks.create!(
        content: "REQUEST_PRIVATE_NO_REQUOTE_ENTRY",
        visibility: :private_jjaek
      )
      sign_in viewer

      get jjaek_path(private_jjaek)

      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: private_jjaek.id))
    end

    it "does not show a requote entry for a requote" do
      sign_in viewer

      get jjaek_path(requote)

      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: requote.id))
    end

    it "blocks a user's own requote when the original is no longer visible to them" do
      sign_in viewer
      requote
      friendship.destroy!

      get jjaek_path(requote)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /" do
    it "shows jjaeks targeted at the viewer in the home feed" do
      original_author.jjaeks.create!(
        target_user: viewer,
        content: "REQUEST_TARGETED_AT_VIEWER_FEED",
        visibility: :book_friends
      )
      sign_in viewer

      get root_path

      expect(response.body).to include("REQUEST_TARGETED_AT_VIEWER_FEED")
      expect(response.body).to include(original_author.name)
      expect(response.body).to include(user_path(original_author))
      expect(response.body).to include(viewer.name)
      expect(response.body).to include(user_path(viewer))
      expect(response.body).to include("님에게 남긴 짹")
    end

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
