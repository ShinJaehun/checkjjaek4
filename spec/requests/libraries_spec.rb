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

      expect(response.body).to include(I18n.t("users.library.title_with_name", name: owner.name))
      expect(response.body).to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include(I18n.t("users.library.title"))
      expect(response.body).to include("LIBRARY_PUBLIC_SHELF")
      expect(response.body).to include("LIBRARY_PUBLIC_BOOK")
    end

    it "shows the user's own library" do
      bookshelf = viewer.bookshelves.create!(name: "SELF_LIBRARY_PRIVATE_SHELF", visibility: :private)
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "SELF_LIBRARY_PRIVATE_BOOK")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id)

      expect(response.body).to include(I18n.t("users.library.title_with_name", name: viewer.name))
      expect(response.body).to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
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

      expect(response.body).to include(I18n.t("users.library.title_with_name", name: owner.name))
      expect(response.body).to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
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

      get user_library_path(viewer, bookshelf_id: first.id, sort: "title", view: "compact")

      document = Nokogiri::HTML(response.body)
      second_tab = document.css("a").find { |link| link.text.include?(second.name) }
      sort_form = document.at_css(%(form[action="#{user_library_path(viewer)}"]))

      expect(second_tab["href"]).to eq(user_library_path(viewer, bookshelf_id: second.id, sort: "title", view: "compact"))
      expect(sort_form).to be_present
    end

    it "renders detail view by default" do
      bookshelf = viewer.bookshelves.create!(name: "LIBRARY_DETAIL_SHELF")
      entry = create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "LIBRARY_DETAIL_BOOK")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id)

      document = Nokogiri::HTML(response.body)
      detail_card = document.at_css(%(article[data-bookshelf-entry-id="#{entry.id}"][data-bookshelf-entry-view="detail"]))
      move_form = document.at_css(%(form[action="#{move_bookshelf_entry_path(entry)}"]))

      expect(detail_card).to be_present
      expect(detail_card.has_attribute?("data-bookshelf-entries-sort-handle")).to be(true)
      expect(detail_card["draggable"]).to be_nil
      expect(detail_card["data-action"]).to be_nil
      expect(move_form).to be_nil
    end

    it "renders compact view when requested" do
      bookshelf = viewer.bookshelves.create!(name: "LIBRARY_COMPACT_SHELF")
      entry = create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "LIBRARY_COMPACT_BOOK")
      first_sticker = StickerDefinition.create!(key: "libraries_spec_compact_first", name: "재미")
      second_sticker = StickerDefinition.create!(key: "libraries_spec_compact_second", name: "여운")
      entry.sticker_definitions << [ first_sticker, second_sticker ]
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id, view: "compact")

      document = Nokogiri::HTML(response.body)
      compact_card = document.at_css(%(article[data-bookshelf-entry-id="#{entry.id}"][data-bookshelf-entry-view="compact"]))
      move_form = document.at_css(%(form[action="#{move_bookshelf_entry_path(entry)}"]))

      expect(compact_card).to be_present
      sticker_badge = compact_card.at_css(%([aria-label="스티커: 재미, 여운"]))

      expect(compact_card.has_attribute?("data-bookshelf-entries-sort-handle")).to be(true)
      expect(compact_card["draggable"]).to be_nil
      expect(compact_card["data-action"]).to be_nil
      expect(sticker_badge).to be_present
      expect(sticker_badge["title"]).to eq("재미, 여운")
      expect(move_form).to be_nil
    end

    it "falls back to detail view for an invalid view mode" do
      bookshelf = viewer.bookshelves.create!(name: "LIBRARY_INVALID_VIEW_SHELF")
      entry = create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "LIBRARY_INVALID_VIEW_BOOK")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id, view: "unknown")

      document = Nokogiri::HTML(response.body)

      expect(document.at_css(%(article[data-bookshelf-entry-id="#{entry.id}"][data-bookshelf-entry-view="detail"]))).to be_present
      expect(document.at_css(%(article[data-bookshelf-entry-id="#{entry.id}"][data-bookshelf-entry-view="compact"]))).to be_nil
    end

    it "keeps bookshelf and sort params in view mode links" do
      bookshelf = viewer.bookshelves.create!(name: "LIBRARY_VIEW_LINK_SHELF")
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "LIBRARY_VIEW_LINK_BOOK")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id, sort: "title")

      document = Nokogiri::HTML(response.body)
      view_toggle = document.at_css("[data-library-summary] [data-library-view-toggle]")

      expect(view_toggle).to be_present

      compact_link = view_toggle.css("a").find do |link|
        link.text.strip == I18n.t("users.library.view_modes.compact")
      end
      detail_link = view_toggle.css("a").find do |link|
        link.text.strip == I18n.t("users.library.view_modes.detail")
      end

      expect(compact_link["href"]).to eq(user_library_path(viewer, bookshelf_id: bookshelf.id, sort: "title", view: "compact"))
      expect(detail_link["href"]).to eq(user_library_path(viewer, bookshelf_id: bookshelf.id, sort: "title", view: "detail"))
    end

    it "shows owner management controls on the library screen" do
      bookshelf = viewer.bookshelves.create!(name: "LIBRARY_MANAGED_SHELF")
      second_bookshelf = viewer.bookshelves.create!(name: "LIBRARY_SECOND_MANAGED_SHELF")
      entry = create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "SELF_LIBRARY_MOVABLE_BOOK")
      sign_in viewer

      get user_library_path(viewer, bookshelf_id: bookshelf.id)

      document = Nokogiri::HTML(response.body)

      expect(response.body).to include(I18n.t("bookshelves.form.title"))
      expect(response.body).to include(I18n.t("bookshelves.form.edit_title"))
      expect(response.body).to include(I18n.t("bookshelves.actions.move_down"))
      expect(response.body).to include(second_bookshelf.name)
      expect(response.body).to include('name="return_to"')
      expect(response.body).to include('value="library"')
      expect(document.at_css(%(form[action="#{move_bookshelf_entry_path(entry)}"]))).to be_nil

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
