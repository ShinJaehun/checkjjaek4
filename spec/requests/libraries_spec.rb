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
      BookFriendship.create!(requester: viewer, addressee: owner, status: :accepted)
      bookshelf = owner.bookshelves.create!(name: "LIBRARY_PUBLIC_SHELF", visibility: :public)
      create_bookshelf_entry(user: owner, bookshelf: bookshelf, book_title: "LIBRARY_PUBLIC_BOOK")
      sign_in viewer

      get user_library_path(owner, bookshelf_id: bookshelf.id)

      expect(response.body).to include(I18n.t("users.profile.bookshelf_title"))
      expect(response.body).not_to include(I18n.t("users.library.title"))
      expect(response.body).to include("LIBRARY_PUBLIC_SHELF")
      expect(response.body).to include("LIBRARY_PUBLIC_BOOK")
    end

    it "shows the user's own library" do
      bookshelf = viewer.bookshelves.create!(name: "SELF_LIBRARY_PRIVATE_SHELF", visibility: :private)
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "SELF_LIBRARY_PRIVATE_BOOK")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id)

      expect(response.body).to include(I18n.t("users.profile.bookshelf_title"))
      expect(response.body).not_to include(I18n.t("users.library.title"))
      expect(response.body).not_to include(I18n.t("users.library.book_friend_read_only_notice"))
      expect(response.body).to include("SELF_LIBRARY_PRIVATE_SHELF")
      expect(response.body).to include("SELF_LIBRARY_PRIVATE_BOOK")
    end

    it "shows an accepted book friend's library" do
      BookFriendship.create!(requester: viewer, addressee: owner, status: :accepted)
      bookshelf = owner.bookshelves.create!(name: "FRIEND_LIBRARY_PUBLIC_SHELF", visibility: :public)
      create_bookshelf_entry(user: owner, bookshelf: bookshelf, book_title: "FRIEND_LIBRARY_PUBLIC_BOOK")
      sign_in viewer

      get user_library_path(owner, bookshelf_id: bookshelf.id)

      expect(response.body).to include(I18n.t("users.profile.bookshelf_title"))
      expect(response.body).not_to include(I18n.t("users.library.title"))
      expect(response.body).to include(I18n.t("users.library.book_friend_read_only_notice"))
      expect(response.body).to include("FRIEND_LIBRARY_PUBLIC_SHELF")
      expect(response.body).to include("FRIEND_LIBRARY_PUBLIC_BOOK")
    end

    it "shows public and book-friends shelves but not private shelves to accepted book friends" do
      BookFriendship.create!(requester: viewer, addressee: owner, status: :accepted)
      public_shelf = owner.bookshelves.create!(name: "LIBRARY_PUBLIC_VISIBLE", visibility: :public)
      friend_shelf = owner.bookshelves.create!(name: "LIBRARY_FRIEND_VISIBLE", visibility: :book_friends)
      private_shelf = owner.bookshelves.create!(name: "LIBRARY_PRIVATE_HIDDEN", visibility: :private)
      sign_in viewer

      get user_library_path(owner, bookshelf_id: public_shelf.id)

      expect(response.body).to include(public_shelf.name)
      expect(response.body).to include(friend_shelf.name)
      expect(response.body).not_to include(private_shelf.name)
    end

    it "redirects strangers to the profile" do
      sign_in viewer

      get user_library_path(owner)

      expect(response).to redirect_to(user_path(owner))
    end

    it "redirects follow-only users to the profile" do
      viewer.active_follows.create!(followee: owner)
      sign_in viewer

      get user_library_path(owner)

      expect(response).to redirect_to(user_path(owner))
    end

    it "still allows follow-only users to see public books on the profile" do
      bookshelf = owner.default_bookshelf
      create_bookshelf_entry(user: owner, bookshelf: bookshelf, book_title: "FOLLOW_PROFILE_PUBLIC_BOOK")
      viewer.active_follows.create!(followee: owner)
      sign_in viewer

      get user_library_path(owner, bookshelf_id: bookshelf.id)
      follow_redirect!

      expect(response.body).to include("FOLLOW_PROFILE_PUBLIC_BOOK")
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
      second_bookshelf = viewer.bookshelves.create!(name: "LIBRARY_SECOND_MANAGED_SHELF")
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "SELF_LIBRARY_MOVABLE_BOOK")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id)

      expect(response.body).to include(I18n.t("bookshelves.form.title"))
      expect(response.body).to include(I18n.t("bookshelves.form.edit_title"))
      expect(response.body).to include(I18n.t("bookshelves.actions.move_down"))
      expect(response.body).to include(I18n.t("bookshelf_entries.actions.move"))
      expect(response.body).to include(second_bookshelf.name)
      expect(response.body).to include('name="return_to"')
      expect(response.body).to include('value="library"')

      get user_library_path(viewer, bookshelf_id: second_bookshelf.id)

      expect(response.body).to include(I18n.t("bookshelves.actions.destroy"))
    end

    it "does not show management controls to accepted book friends" do
      BookFriendship.create!(requester: viewer, addressee: owner, status: :accepted)
      bookshelf = owner.bookshelves.create!(name: "FRIEND_NO_MANAGE_SHELF", visibility: :public)
      sign_in viewer

      get user_library_path(owner, bookshelf_id: bookshelf.id)

      expect(response.body).to include(I18n.t("users.library.book_friend_read_only_notice"))
      expect(response.body).not_to include(I18n.t("bookshelves.form.title"))
      expect(response.body).not_to include(I18n.t("bookshelves.form.edit_title"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.destroy"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.move_up"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.move_down"))
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))
      expect(response.body).not_to include('name="return_to"')
    end
  end

  def create_bookshelf_entry(user:, bookshelf:, book_title:)
    book = Book.create!(title: book_title, authors_text: "Library Author")

    user.bookshelf_entries.create!(book: book, bookshelf: bookshelf)
  end
end
