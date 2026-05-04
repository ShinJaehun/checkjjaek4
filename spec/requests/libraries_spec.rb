require "rails_helper"

RSpec.describe "Libraries", type: :request do
  let!(:viewer) { User.create!(name: "Library Viewer", email: "library-viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:owner) { User.create!(name: "Library Owner", email: "library-owner@example.com", password: "password123!", password_confirmation: "password123!") }

  describe "GET /users/:user_id/library" do
    it "redirects guests to sign in" do
      get user_library_path(owner)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the owner's accessible bookshelf tabs and entries" do
      bookshelf = owner.bookshelves.create!(name: "LIBRARY_PUBLIC_SHELF", visibility: :public)
      create_bookshelf_entry(user: owner, bookshelf: bookshelf, book_title: "LIBRARY_PUBLIC_BOOK")
      sign_in viewer

      get user_library_path(owner, bookshelf_id: bookshelf.id)

      expect(response.body).to include(I18n.t("users.library.title"))
      expect(response.body).to include("LIBRARY_PUBLIC_SHELF")
      expect(response.body).to include("LIBRARY_PUBLIC_BOOK")
    end

    it "keeps library path in bookshelf tab and sort links" do
      first = viewer.bookshelves.create!(name: "LIBRARY_FIRST")
      second = viewer.bookshelves.create!(name: "LIBRARY_SECOND")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: first.id, sort: "title")

      expect(response.body).to include(CGI.escapeHTML(user_library_path(viewer, bookshelf_id: second.id, sort: "title")))
      expect(response.body).to include(%(action="#{user_library_path(viewer)}"))
    end

    it "shows owner management controls on the library screen" do
      bookshelf = viewer.bookshelves.create!(name: "LIBRARY_MANAGED_SHELF")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id)

      expect(response.body).to include(I18n.t("bookshelves.form.title"))
      expect(response.body).to include(I18n.t("bookshelves.form.edit_title"))
      expect(response.body).to include('name="return_to"')
      expect(response.body).to include('value="library"')
    end
  end

  def create_bookshelf_entry(user:, bookshelf:, book_title:)
    book = Book.create!(title: book_title, authors_text: "Library Author")

    user.bookshelf_entries.create!(book: book, bookshelf: bookshelf)
  end
end
