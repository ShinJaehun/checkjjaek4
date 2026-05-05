require "rails_helper"

RSpec.describe "Users", type: :request do
  let!(:viewer) { User.create!(name: "Viewer", email: "viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:profile_user) { User.create!(name: "Profile User", email: "profile@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:other_user) { User.create!(name: "Other", email: "other@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "프로필 책", authors_text: "저자") }
  let!(:shelf_book) { Book.create!(title: "프로필 서재 전용 책", authors_text: "저자") }
  let!(:profile_shelf_sticker) { StickerDefinition.create!(key: "users_spec_profile_shelf_unique_sticker", name: "PROFILE_SHELF_UNIQUE_STICKER") }
  let!(:profile_entry) { profile_user.bookshelf_entries.create!(book: shelf_book, status: :reading) }
  let!(:profile_jjaek) { profile_user.jjaeks.create!(book:, content: "Profile Jjaek") }
  let!(:profile_friend_jjaek) { profile_user.jjaeks.create!(content: "Book friend profile Jjaek", visibility: :book_friends) }
  let!(:profile_private_jjaek) { profile_user.jjaeks.create!(content: "Private profile Jjaek", visibility: :private_jjaek) }
  let!(:other_jjaek) { other_user.jjaeks.create!(book:, content: "Other private", visibility: :private_jjaek) }
  let!(:activity_book) { Book.create!(title: "프로필 활동 책", authors_text: "저자") }

  before do
    profile_entry.sticker_definitions << profile_shelf_sticker
  end

  describe "GET /users/:id" do
    it "redirects guests to sign in" do
      get user_path(profile_user)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows public books summary and only public jjaeks to unrelated users" do
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include(I18n.t("users.profile.public_books_title"))
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_title"))
      expect(response.body).to include("프로필 서재 전용 책")
      expect(response.body).to include("저자")
      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_sort.label"))
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))
      expect(response.body).not_to include(I18n.t("bookshelf_entries.statuses.reading"))
      expect(response.body).not_to include("PROFILE_SHELF_UNIQUE_STICKER")
      expect(response.body).not_to include(I18n.t("users.profile.view_library"))
      expect(response.body).to include("Profile Jjaek")
      expect(response.body).not_to include("Book friend profile Jjaek")
      expect(response.body).not_to include("Private profile Jjaek")
      expect(response.body).not_to include("Other private")
      expect(response.body).to include(I18n.t("users.profile.activity_title"))
    end

    it "shows public books summary and only public jjaeks to follow-only users" do
      viewer.active_follows.create!(followee: profile_user)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include(I18n.t("users.profile.public_books_title"))
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_title"))
      expect(response.body).to include("프로필 서재 전용 책")
      expect(response.body).to include("Profile Jjaek")
      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_sort.label"))
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))
      expect(response.body).not_to include(I18n.t("bookshelf_entries.statuses.reading"))
      expect(response.body).not_to include("PROFILE_SHELF_UNIQUE_STICKER")
      expect(response.body).not_to include(I18n.t("users.profile.view_library"))
      expect(response.body).not_to include("Book friend profile Jjaek")
      expect(response.body).not_to include("Private profile Jjaek")
      expect(response.body).to include(I18n.t("users.profile.activity_title"))
    end

    it "shows summarized shelf entries, book-friend jjaeks, and a profile-context form to accepted book friends" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include(I18n.t("users.profile.public_books_title"))
      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_sort.label"))
      expect(response.body).not_to include(I18n.t("bookshelves.form.title"))
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))
      expect(response.body).to include("프로필 서재 전용 책")
      expect(response.body).to include(I18n.t("bookshelf_entries.statuses.reading"))
      expect(response.body).to include("PROFILE_SHELF_UNIQUE_STICKER")
      expect(response.body).to include("Profile Jjaek")
      expect(response.body).to include("Book friend profile Jjaek")
      expect(response.body).not_to include("Private profile Jjaek")
      expect(response.body).to include(I18n.t("users.profile.view_library"))
      expect(response.body).to include(user_library_path(profile_user))
      expect(response.body).to include('name="jjaek[target_user_id]"')
      expect(response.body).to include(I18n.t("jjaeks.visibility.book_friends"))
    end

    it "shows the user's own summarized shelf, library link, private jjaeks, and profile-context form" do
      own_book = Book.create!(title: "내 책", authors_text: "저자")
      own_sticker = StickerDefinition.create!(key: "users_spec_own_profile_shelf_sticker", name: "OWN_PROFILE_SHELF_STICKER")
      own_entry = viewer.bookshelf_entries.create!(book: own_book, status: :finished)
      own_entry.sticker_definitions << own_sticker
      viewer.jjaeks.create!(content: "내 비공개 짹", visibility: :private_jjaek)
      sign_in viewer

      get user_path(viewer)

      expect(response.body).to include("내 책")
      expect(response.body).to include(I18n.t("bookshelf_entries.statuses.finished"))
      expect(response.body).to include("OWN_PROFILE_SHELF_STICKER")
      expect(response.body).to include("내 비공개 짹")
      expect(response.body).to include(I18n.t("users.profile.public_books_title"))
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_title"))
      expect(response.body).to include(I18n.t("users.profile.view_library"))
      expect(response.body).to include(user_library_path(viewer))
      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_sort.label"))
      expect(response.body).not_to include(I18n.t("bookshelves.form.title"))
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))
      expect(response.body).to include('name="jjaek[target_user_id]"')
      expect(response.body).to include(I18n.t("jjaeks.visibility.private_jjaek"))
    end

    it "shows an empty public books message to unrelated users without library controls" do
      profile_user.bookshelf_entries.destroy_all
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include(I18n.t("users.profile.empty_public_books"))
      expect(response.body).not_to include(I18n.t("users.profile.view_library"))
      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
    end

    it "shows the owner private books summary without bookshelf tabs" do
      create_profile_bookshelf_entry(
        user: viewer,
        bookshelf_name: "OWNER_PRIVATE_TAB_SHELF",
        visibility: :private,
        book_title: "OWNER_PRIVATE_TAB_BOOK"
      )
      sign_in viewer

      get user_path(viewer)

      expect(response.body).to include("OWNER_PRIVATE_TAB_BOOK")
      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include("OWNER_PRIVATE_TAB_SHELF")
    end

    it "does not show the bookshelf create form on the user's own profile" do
      sign_in viewer

      get user_path(viewer)

      expect(response.body).not_to include(I18n.t("bookshelves.form.title"))
      expect(response.body).not_to include('name="bookshelf[name]"')
      expect(response.body).not_to include('name="bookshelf[visibility]"')
      expect(response.body).not_to include('name="bookshelf[color_key]"')
    end

    it "does not show bookshelf edit and delete controls for an owned empty non-default bookshelf on the profile" do
      bookshelf = viewer.bookshelves.create!(name: "관리할 빈 책장", visibility: :private, color_key: "green")
      sign_in viewer

      get user_path(viewer, bookshelf_id: bookshelf.id)

      expect(response.body).not_to include(I18n.t("bookshelves.form.edit_title"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.update"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.destroy"))
      expect(response.body).not_to include('name="bookshelf[color_key]"')
      expect(response.body).not_to include("bg-green-600")
    end

    it "does not show bookshelf ordering controls for an owned regular bookshelf on the profile" do
      viewer.bookshelves.create!(name: "순서 앞 책장")
      bookshelf = viewer.bookshelves.create!(name: "순서 가운데 책장")
      viewer.bookshelves.create!(name: "순서 뒤 책장")
      sign_in viewer

      get user_path(viewer, bookshelf_id: bookshelf.id)

      expect(response.body).not_to include(I18n.t("bookshelves.actions.move_up"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.move_down"))
    end

    it "does not show bookshelf edit or delete controls for the default bookshelf" do
      sign_in viewer

      get user_path(viewer, bookshelf_id: viewer.default_bookshelf.id)

      expect(response.body).not_to include(I18n.t("bookshelves.form.edit_title"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.update"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.destroy"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.move_up"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.move_down"))
    end

    it "does not show bookshelf edit or delete controls on another user's profile" do
      bookshelf = profile_user.bookshelves.create!(name: "타인 관리 숨김 책장", visibility: :public)
      sign_in viewer

      get user_path(profile_user, bookshelf_id: bookshelf.id)

      expect(response.body).not_to include(I18n.t("bookshelves.form.edit_title"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.update"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.destroy"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.move_up"))
      expect(response.body).not_to include(I18n.t("bookshelves.actions.move_down"))
    end

    it "does not show bookshelf tabs after moving bookshelf order" do
      first = viewer.bookshelves.create!(name: "ORDER_BEFORE")
      second = viewer.bookshelves.create!(name: "ORDER_AFTER")
      sign_in viewer

      patch move_down_bookshelf_path(first)
      get user_path(viewer, bookshelf_id: first.id)

      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include(user_path(viewer, bookshelf_id: first.id))
      expect(response.body).not_to include(user_path(viewer, bookshelf_id: second.id))
    end

    it "does not show bookshelf tab color or management controls on another user's profile" do
      bookshelf = profile_user.bookshelves.create!(name: "색상 보이는 책장", visibility: :public, color_key: "blue")
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      get user_path(profile_user, bookshelf_id: bookshelf.id)

      expect(response.body).not_to include("bg-blue-600")
      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include(I18n.t("bookshelves.form.edit_title"))
      expect(response.body).not_to include('name="bookshelf[color_key]"')
    end

    it "does not show the bookshelf create form on another user's profile" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      get user_path(profile_user)
      expect(response.body).not_to include('name="bookshelf[name]"')

      sign_out viewer
      stranger_viewer = User.create!(name: "Create Form Stranger", email: "create-form-stranger@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in stranger_viewer

      get user_path(profile_user)
      expect(response.body).not_to include('name="bookshelf[name]"')

      stranger_viewer.active_follows.create!(followee: profile_user)
      get user_path(profile_user)
      expect(response.body).not_to include('name="bookshelf[name]"')
    end

    it "shows public and book-friends books summary without bookshelf tabs to accepted book friends" do
      create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "FRIEND_VISIBLE_TAB_SHELF",
        visibility: :book_friends,
        book_title: "FRIEND_VISIBLE_TAB_BOOK"
      )
      create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "FRIEND_HIDDEN_PRIVATE_TAB_SHELF",
        visibility: :private,
        book_title: "FRIEND_HIDDEN_PRIVATE_TAB_BOOK"
      )
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).to include("FRIEND_VISIBLE_TAB_BOOK")
      expect(response.body).not_to include("FRIEND_HIDDEN_PRIVATE_TAB_SHELF")
      expect(response.body).not_to include("FRIEND_HIDDEN_PRIVATE_TAB_BOOK")
    end

    it "does not show bookshelf tabs to strangers" do
      create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "STRANGER_HIDDEN_FRIEND_TAB_SHELF",
        visibility: :book_friends,
        book_title: "STRANGER_HIDDEN_FRIEND_TAB_BOOK"
      )
      create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "STRANGER_HIDDEN_PRIVATE_TAB_SHELF",
        visibility: :private,
        book_title: "STRANGER_HIDDEN_PRIVATE_TAB_BOOK"
      )
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include("STRANGER_HIDDEN_FRIEND_TAB_SHELF")
      expect(response.body).not_to include("STRANGER_HIDDEN_PRIVATE_TAB_SHELF")
    end

    it "does not show bookshelf tabs to follow-only users" do
      viewer.active_follows.create!(followee: profile_user)
      create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "FOLLOW_ONLY_HIDDEN_FRIEND_TAB_SHELF",
        visibility: :book_friends,
        book_title: "FOLLOW_ONLY_HIDDEN_FRIEND_TAB_BOOK"
      )
      create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "FOLLOW_ONLY_HIDDEN_PRIVATE_TAB_SHELF",
        visibility: :private,
        book_title: "FOLLOW_ONLY_HIDDEN_PRIVATE_TAB_BOOK"
      )
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).not_to include("FOLLOW_ONLY_HIDDEN_FRIEND_TAB_SHELF")
      expect(response.body).not_to include("FOLLOW_ONLY_HIDDEN_PRIVATE_TAB_SHELF")
    end

    it "does not use selected bookshelf tabs on an accepted book friend's profile" do
      selected_shelf, = create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "SELECTED_TAB_SHELF",
        visibility: :public,
        book_title: "SELECTED_TAB_BOOK"
      )
      create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "UNSELECTED_TAB_SHELF",
        visibility: :public,
        book_title: "UNSELECTED_TAB_BOOK"
      )
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      get user_path(profile_user, bookshelf_id: selected_shelf.id)

      expect(response.body).not_to include(%(aria-label="#{I18n.t("users.profile.bookshelf_tabs")}"))
      expect(response.body).to include("SELECTED_TAB_BOOK")
      expect(response.body).to include("UNSELECTED_TAB_BOOK")
      expect(response.body).to include("프로필 서재 전용 책")
    end

    it "keeps recent sort by default" do
      bookshelf = viewer.bookshelves.create!(name: "RECENT_SORT_SHELF")
      older = create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "RECENT_SORT_OLDER")
      newer = create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "RECENT_SORT_NEWER")
      older.update!(updated_at: 2.days.ago)
      newer.update!(updated_at: 1.day.ago)
      sign_in viewer

      get user_path(viewer, bookshelf_id: bookshelf.id)

      expect_text_order("RECENT_SORT_NEWER", "RECENT_SORT_OLDER")
    end

    it "does not sort profile summary entries by title param" do
      bookshelf = viewer.bookshelves.create!(name: "TITLE_SORT_SHELF")
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "TITLE_SORT_Z")
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "TITLE_SORT_A")
      sign_in viewer

      get user_path(viewer, bookshelf_id: bookshelf.id, sort: "title")

      expect(response.body).to include("TITLE_SORT_Z")
      expect(response.body).to include("TITLE_SORT_A")
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_sort.label"))
    end

    it "does not sort profile summary entries by author param" do
      bookshelf = viewer.bookshelves.create!(name: "AUTHOR_SORT_SHELF")
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "AUTHOR_SORT_B_BOOK", authors_text: "ZZZ Author")
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "AUTHOR_SORT_A_BOOK", authors_text: "AAA Author")
      sign_in viewer

      get user_path(viewer, bookshelf_id: bookshelf.id, sort: "author")

      expect(response.body).to include("AUTHOR_SORT_B_BOOK")
      expect(response.body).to include("AUTHOR_SORT_A_BOOK")
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_sort.label"))
    end

    it "does not sort profile summary entries by status param" do
      bookshelf = viewer.bookshelves.create!(name: "STATUS_SORT_SHELF")
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "STATUS_SORT_FINISHED", status: :finished)
      create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "STATUS_SORT_WISH", status: :wish)
      sign_in viewer

      get user_path(viewer, bookshelf_id: bookshelf.id, sort: "status")

      expect(response.body).to include("STATUS_SORT_FINISHED")
      expect(response.body).to include("STATUS_SORT_WISH")
      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_sort.label"))
    end

    it "falls back to recent sort for unsupported sort values" do
      bookshelf = viewer.bookshelves.create!(name: "BAD_SORT_SHELF")
      older = create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "BAD_SORT_OLDER")
      newer = create_bookshelf_entry(user: viewer, bookshelf: bookshelf, book_title: "BAD_SORT_NEWER")
      older.update!(updated_at: 2.days.ago)
      newer.update!(updated_at: 1.day.ago)
      sign_in viewer

      get user_path(viewer, bookshelf_id: bookshelf.id, sort: "unknown")

      expect_text_order("BAD_SORT_NEWER", "BAD_SORT_OLDER")
    end

    it "does not filter profile summary entries by selected bookshelf" do
      selected_shelf = viewer.bookshelves.create!(name: "SELECTED_SORT_SHELF")
      unselected_shelf = viewer.bookshelves.create!(name: "UNSELECTED_SORT_SHELF")
      create_bookshelf_entry(user: viewer, bookshelf: selected_shelf, book_title: "SELECTED_SORT_BOOK")
      create_bookshelf_entry(user: viewer, bookshelf: unselected_shelf, book_title: "UNSELECTED_SORT_BOOK")
      sign_in viewer

      get user_path(viewer, bookshelf_id: selected_shelf.id, sort: "title")

      expect(response.body).to include("SELECTED_SORT_BOOK")
      expect(response.body).to include("UNSELECTED_SORT_BOOK")
    end

    it "keeps status and stickers hidden from strangers when sorting" do
      bookshelf = profile_user.bookshelves.create!(name: "STRANGER_SORT_SHELF", visibility: :public)
      entry = create_bookshelf_entry(user: profile_user, bookshelf: bookshelf, book_title: "STRANGER_SORT_BOOK", status: :finished)
      entry.sticker_definitions << profile_shelf_sticker
      sign_in viewer

      get user_path(profile_user, bookshelf_id: bookshelf.id, sort: "status")

      expect(response.body).to include("STRANGER_SORT_BOOK")
      expect(response.body).not_to include(I18n.t("bookshelf_entries.statuses.finished"))
      expect(response.body).not_to include("PROFILE_SHELF_UNIQUE_STICKER")
    end

    it "does not show bookshelf tab sort links on the profile" do
      first_shelf = viewer.bookshelves.create!(name: "SORT_LINK_FIRST")
      second_shelf = viewer.bookshelves.create!(name: "SORT_LINK_SECOND")
      sign_in viewer

      get user_path(viewer, bookshelf_id: first_shelf.id, sort: "title")

      expect(response.body).not_to include(CGI.escapeHTML(user_path(viewer, bookshelf_id: second_shelf.id, sort: "title")))
    end

    it "does not show the bookshelf entry sort UI on the profile" do
      sign_in viewer

      get user_path(viewer)

      expect(response.body).not_to include(I18n.t("users.profile.bookshelf_sort.label"))
      expect(response.body).not_to include('name="sort"')
    end

    it "falls back to an accessible bookshelf when the requested bookshelf is not allowed" do
      hidden_shelf, = create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "FALLBACK_HIDDEN_PRIVATE_TAB_SHELF",
        visibility: :private,
        book_title: "FALLBACK_HIDDEN_PRIVATE_TAB_BOOK"
      )
      sign_in viewer

      get user_path(profile_user, bookshelf_id: hidden_shelf.id)

      expect(response.body).to include("프로필 서재 전용 책")
      expect(response.body).not_to include("FALLBACK_HIDDEN_PRIVATE_TAB_BOOK")
    end

    it "shows status and stickers in a summarized bookshelf entry to the owner" do
      selected_shelf, = create_profile_bookshelf_entry(
        user: viewer,
        bookshelf_name: "OWNER_DETAILS_TAB_SHELF",
        visibility: :private,
        book_title: "OWNER_DETAILS_TAB_BOOK",
        status: :finished,
        sticker_name: "OWNER_DETAILS_UNIQUE_STICKER"
      )
      sign_in viewer

      get user_path(viewer, bookshelf_id: selected_shelf.id)

      expect(response.body).to include(I18n.t("bookshelf_entries.statuses.finished"))
      expect(response.body).to include("OWNER_DETAILS_UNIQUE_STICKER")
    end

    it "shows status and stickers in a summarized bookshelf entry to accepted book friends" do
      selected_shelf, = create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "FRIEND_DETAILS_TAB_SHELF",
        visibility: :book_friends,
        book_title: "FRIEND_DETAILS_TAB_BOOK",
        status: :finished,
        sticker_name: "FRIEND_DETAILS_UNIQUE_STICKER"
      )
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      get user_path(profile_user, bookshelf_id: selected_shelf.id)

      expect(response.body).to include("FRIEND_DETAILS_TAB_BOOK")
      expect(response.body).to include(I18n.t("bookshelf_entries.statuses.finished"))
      expect(response.body).to include("FRIEND_DETAILS_UNIQUE_STICKER")
    end

    it "hides status and stickers in a public bookshelf from strangers" do
      selected_shelf, = create_profile_bookshelf_entry(
        user: profile_user,
        bookshelf_name: "STRANGER_DETAILS_TAB_SHELF",
        visibility: :public,
        book_title: "STRANGER_DETAILS_TAB_BOOK",
        status: :finished,
        sticker_name: "STRANGER_DETAILS_UNIQUE_STICKER"
      )
      sign_in viewer

      get user_path(profile_user, bookshelf_id: selected_shelf.id)

      expect(response.body).to include("STRANGER_DETAILS_TAB_BOOK")
      expect(response.body).not_to include(I18n.t("bookshelf_entries.statuses.finished"))
      expect(response.body).not_to include("STRANGER_DETAILS_UNIQUE_STICKER")
    end

    it "does not show the bookshelf move select on the owner's profile" do
      viewer.bookshelf_entries.create!(book: Book.create!(title: "MOVE_SELECT_VISIBLE_BOOK", authors_text: "저자"))
      sign_in viewer

      get user_path(viewer)

      expect(response.body).not_to include('name="bookshelf_id"')
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))
    end

    it "does not show the bookshelf move select to accepted book friends, strangers, or follow-only users" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      get user_path(profile_user)
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))

      sign_out viewer
      stranger_viewer = User.create!(name: "Stranger Viewer", email: "stranger-viewer@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in stranger_viewer

      get user_path(profile_user)
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))

      stranger_viewer.active_follows.create!(followee: profile_user)
      get user_path(profile_user)
      expect(response.body).not_to include(I18n.t("bookshelf_entries.actions.move"))
    end

    it "labels a self-targeted profile jjaek as the user's general jjaek" do
      viewer.jjaeks.create!(target_user: viewer, content: "SELF_TARGETED_PROFILE_JJAEK", visibility: :private_jjaek)
      sign_in viewer

      get user_path(viewer)

      expect(page_text).to include("Viewer님의 짹")
      expect(page_text).not_to include("Viewer님이 Viewer님에게 남긴 짹")
      expect(response.body).to include("SELF_TARGETED_PROFILE_JJAEK")
    end

    it "shows the user's own Jjaeks and BookActivity in one recent activity section" do
      viewer.jjaeks.create!(content: "내 최근 짹", visibility: :private_jjaek)
      BookActivity.create!(user: viewer, book: activity_book, action: :added_to_shelf)
      sign_in viewer

      get user_path(viewer)

      expect(response.body).to include(I18n.t("users.profile.activity_title"))
      expect(response.body).not_to include("책 활동")
      expect(response.body).not_to include("최근 Jjaek")
      expect(response.body).to include("내 최근 짹")
      expect(page_text).to include("Viewer님이 『프로필 활동 책』를 서재에 담았습니다.")
    end

    it "shows an empty recent activity message on the user's own profile" do
      sign_in viewer

      get user_path(viewer)

      expect(response.body).to include(I18n.t("users.profile.activity_title"))
      expect(response.body).to include(I18n.t("users.profile.empty_activity"))
    end

    it "shows visible Jjaeks and BookActivity on an accepted book friend's profile" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      BookActivity.create!(user: profile_user, book: activity_book, action: :added_to_shelf)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include(I18n.t("users.profile.activity_title"))
      expect(response.body).to include("Profile Jjaek")
      expect(response.body).to include("Book friend profile Jjaek")
      expect(page_text).to include("Profile User님이 『프로필 활동 책』를 서재에 담았습니다.")
    end

    it "does not show BookActivity on a stranger's profile" do
      BookActivity.create!(user: profile_user, book: activity_book, action: :added_to_shelf)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include(I18n.t("users.profile.activity_title"))
      expect(response.body).not_to include("프로필 활동 책")
    end

    it "does not show BookActivity on a follow-only user's profile" do
      viewer.active_follows.create!(followee: profile_user)
      BookActivity.create!(user: profile_user, book: activity_book, action: :added_to_shelf)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).to include(I18n.t("users.profile.activity_title"))
      expect(response.body).not_to include("프로필 활동 책")
    end

    it "shows each BookActivity action message on the profile" do
      sticker = StickerDefinition.create!(key: "users_spec_memorable", name: "기억나요")
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      BookActivity.create!(user: profile_user, book: activity_book, action: :added_to_shelf)
      BookActivity.create!(user: profile_user, book: activity_book, action: :status_changed, metadata: { to_status: "finished" })
      BookActivity.create!(user: profile_user, book: activity_book, action: :status_cleared)
      BookActivity.create!(user: profile_user, book: activity_book, action: :sticker_added, metadata: { sticker_definition_id: sticker.id, sticker_name: sticker.name })
      BookActivity.create!(user: profile_user, book: activity_book, action: :sticker_removed, metadata: { sticker_definition_id: sticker.id, sticker_name: sticker.name })
      sign_in viewer

      get user_path(profile_user)

      expect(page_text).to include("Profile User님이 『프로필 활동 책』를 서재에 담았습니다.")
      expect(page_text).to include("Profile User님이 『프로필 활동 책』를 읽었어요로 바꿨습니다.")
      expect(page_text).to include("Profile User님이 『프로필 활동 책』 상태 비움")
      expect(page_text).to include("Profile User님이 『프로필 활동 책』에 기억나요 스티커를 붙였습니다.")
      expect(page_text).to include("Profile User님이 『프로필 활동 책』에서 기억나요 스티커를 제거했습니다.")
    end

    it "orders visible profile Jjaeks and BookActivity together by created_at" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      older_jjaek = profile_user.jjaeks.create!(
        content: "PROFILE_TIMELINE_OLD_JJAEK",
        visibility: :book_friends,
        created_at: 3.hours.ago
      )
      middle_activity = BookActivity.create!(
        user: profile_user,
        book: activity_book,
        action: :added_to_shelf,
        created_at: 2.hours.ago
      )
      newer_jjaek = profile_user.jjaeks.create!(
        content: "PROFILE_TIMELINE_NEW_JJAEK",
        visibility: :public_jjaek,
        created_at: 1.hour.ago
      )
      sign_in viewer

      get user_path(profile_user)

      newer_index = page_text.index(newer_jjaek.content)
      activity_index = page_text.index("Profile User님이 『#{middle_activity.book.title}』를 서재에 담았습니다.")
      older_index = page_text.index(older_jjaek.content)

      expect(newer_index).to be < activity_index
      expect(activity_index).to be < older_index
    end

    it "shows an accepted book friend's BookActivity in the home feed" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      BookActivity.create!(user: profile_user, book: activity_book, action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).not_to include("책 활동")
      expect(page_text).to include("Profile User님이 『프로필 활동 책』를 서재에 담았습니다.")
    end

    it "does not show a profile-context form to unrelated users even when public jjaeks are visible" do
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).not_to include('name="jjaek[target_user_id]"')
    end

    it "does not show a profile-context form to follow-only users" do
      viewer.active_follows.create!(followee: profile_user)
      sign_in viewer

      get user_path(profile_user)

      expect(response.body).not_to include('name="jjaek[target_user_id]"')
    end

    it "rerenders the profile-context form when a profile-context jjaek is invalid" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            target_user_id: profile_user.id,
            content: "",
            visibility: :book_friends
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('name="jjaek[target_user_id]"')
    end

    it "does not create a profile-context jjaek when the viewer cannot write in that profile context" do
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            target_user_id: profile_user.id,
            content: "UNRELATED_PROFILE_CONTEXT_JJAEK",
            visibility: :book_friends
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to redirect_to(root_path)
    end

    it "creates a profile-context jjaek and returns to the home feed" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            target_user_id: profile_user.id,
            content: "PROFILE_CONTEXT_CREATED",
            visibility: :book_friends
          }
        }
      }.to change(Jjaek, :count).by(1)

      created_jjaek = Jjaek.last
      expect(created_jjaek.user).to eq(viewer)
      expect(created_jjaek.target_user).to eq(profile_user)
      expect(response).to redirect_to(root_path)
    end

    it "does not create a private profile-context jjaek for another user" do
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            target_user_id: profile_user.id,
            content: "PRIVATE_PROFILE_CONTEXT_JJAEK",
            visibility: :private_jjaek
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('name="jjaek[target_user_id]"')
      expect(response.body).to include(I18n.t("activerecord.errors.models.jjaek.attributes.visibility.invalid"))
    end

    it "does not reach persistence for an unknown target user" do
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            target_user_id: User.maximum(:id).to_i + 100,
            content: "UNKNOWN_TARGET_USER_CONTEXT_JJAEK",
            visibility: :book_friends
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  def page_text
    ActionView::Base.full_sanitizer.sanitize(response.body)
  end

  def expect_text_order(first_text, second_text)
    first_index = page_text.index(first_text)
    second_index = page_text.index(second_text)

    expect(first_index).to be_present
    expect(second_index).to be_present
    expect(first_index).to be < second_index
  end

  def create_profile_bookshelf_entry(user:, bookshelf_name:, visibility:, book_title:, status: nil, sticker_name: nil, color_key: "stone")
    bookshelf = user.bookshelves.create!(name: bookshelf_name, visibility: visibility, color_key: color_key)
    entry = create_bookshelf_entry(user: user, bookshelf: bookshelf, book_title: book_title, status: status)

    if sticker_name
      sticker = StickerDefinition.create!(key: "users_spec_#{sticker_name.downcase}", name: sticker_name)
      entry.sticker_definitions << sticker
    end

    [ bookshelf, entry ]
  end

  def create_bookshelf_entry(user:, bookshelf:, book_title:, status: nil, authors_text: "탭 테스트 저자")
    book = Book.create!(title: book_title, authors_text: authors_text)

    user.bookshelf_entries.create!(book: book, bookshelf: bookshelf, status: status)
  end
end
