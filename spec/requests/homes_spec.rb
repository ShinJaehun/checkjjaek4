require "rails_helper"

RSpec.describe "Homes", type: :request do
  let(:viewer) { User.create!(name: "Viewer", email: "home-viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book_friend) { User.create!(name: "Book Friend", email: "home-book-friend@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:followee) { User.create!(name: "Followee", email: "home-followee@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:stranger) { User.create!(name: "Stranger", email: "home-stranger@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:viewer_book) { Book.create!(title: "내 활동 책", authors_text: "저자") }
  let(:friend_book) { Book.create!(title: "책친구 활동 책", authors_text: "저자") }
  let(:followee_book) { Book.create!(title: "소식받기 활동 책", authors_text: "저자") }
  let(:stranger_book) { Book.create!(title: "낯선 활동 책", authors_text: "저자") }

  describe "GET /" do
    it "starts with the inline general Jjaek form and feed without the introduction card" do
      sign_in viewer

      get root_path

      expect(response).to have_http_status(:ok)
      main = Nokogiri::HTML(response.body).at_css("main")
      expect(main.at_css("h1")).to be_nil
      expect(main.text).not_to include(
        I18n.t("home.description"), I18n.t("home.actions.search_books"), I18n.t("home.actions.my_shelf")
      )
      form = main.at_css("form[action='#{jjaeks_path}']")
      expect(form).to be_present
      expect(form.ancestors("dialog")).to be_empty
      expect(form.at_css("textarea[name='jjaek[content]']")).to be_present
      visibility_choices = form.css("input[type='radio'][name='jjaek[visibility]']")
      expect(visibility_choices.map { |input| input["value"] }).to eq(Jjaek.visibilities.keys)
      expect(visibility_choices.select { |input| input["checked"] }.map { |input| input["value"] }).to eq([ "public_jjaek" ])
      expect(visibility_choices.all? { |input| input.parent.name == "label" && input.parent.at_css("svg") }).to be(true)
      expect(form.at_css("fieldset legend").text).to eq(I18n.t("jjaeks.form.visibility"))
      expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("jjaeks.actions.publish_short"))
      expect(main.at_css("#feed-items")).to be_present
    end

    it "shows the viewer's own BookActivity in the home feed" do
      BookActivity.create!(user: viewer, book: viewer_book, bookshelf_entry: viewer.bookshelf_entries.find_or_create_by!(book: viewer_book), action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(page_text).to include("Viewer님이 책을 서재에 담았습니다.")
      expect(page_text).not_to include("서재에 담은 책")
    end

    it "shows shelf addition card links and thumbnail fallback" do
      activity = BookActivity.create!(
        user: viewer,
        book: viewer_book,
        bookshelf_entry: viewer.bookshelf_entries.find_or_create_by!(book: viewer_book),
        action: :added_to_shelf
      )
      sign_in viewer

      get root_path

      expect(response.body).to include(user_path(viewer))
      expect(response.body).to include(book_path(viewer_book))
      expect(response.body).to include(I18n.t("book_activities.card.no_thumbnail"))
      card = Nokogiri::HTML(response.body).at_css("#book_activity_#{activity.id}")
      expect(card.at_css("p.leading-6").text).to eq("Viewer님이 책을 서재에 담았습니다.")
      expect(card.text).to include(viewer_book.title, viewer_book.authors_text)
      expect(card.css("[data-reading-status], [data-reading-sticker]")).to be_empty
    end

    it "hides past additions from both feeds after a bookshelf becomes private" do
      viewer.active_follows.create!(followee: book_friend)
      BookFriendship.create!(requester: viewer, addressee: book_friend, status: :accepted)
      shelf = book_friend.bookshelves.create!(name: "Feed shelf", visibility: :public)
      entry = book_friend.bookshelf_entries.create!(book: friend_book, bookshelf: shelf)
      entry.book_activities.create!(user: book_friend, book: friend_book, action: :added_to_shelf)
      update_activity = entry.book_activities.create!(user: book_friend, book: friend_book, action: :bookshelf_entry_updated, metadata: { to_status: "finished" })
      sign_in viewer

      [ root_path, user_path(book_friend) ].each do |path|
        get path
        expect(page_text).to include("Book Friend님이 책을 서재에 담았습니다.")
        expect(response.body).not_to include(%(id="book_activity_#{update_activity.id}"))
      end

      shelf.update!(visibility: :private)
      [ root_path, user_path(book_friend) ].each do |path|
        get path
        expect(page_text).not_to include("Book Friend님이 책을 서재에 담았습니다.")
      end

      sign_in book_friend
      get root_path
      expect(page_text).to include("Book Friend님이 책을 서재에 담았습니다.")
    end

    it "links the shelf entry point to the current user's library" do
      sign_in viewer

      get root_path

      expect(response.body).to include(CGI.escapeHTML(user_library_path(viewer)))
    end

    it "keeps an unfollowed book friend's Jjaeks and BookActivity off the home feed while preserving profile access" do
      BookFriendship.create!(requester: viewer, addressee: book_friend, status: :accepted)
      book_friend.jjaeks.create!(content: "FRIEND_ONLY_PUBLIC_JJAEK", visibility: :public_jjaek)
      book_friend.jjaeks.create!(book: friend_book, content: "FRIEND_ONLY_BOOK_JJAEK", visibility: :book_friends)
      BookActivity.create!(user: book_friend, book: friend_book, bookshelf_entry: book_friend.bookshelf_entries.find_or_create_by!(book: friend_book), action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).not_to include("FRIEND_ONLY_PUBLIC_JJAEK", "FRIEND_ONLY_BOOK_JJAEK")
      expect(page_text).not_to include("Book Friend님이 책을 서재에 담았습니다.")

      get user_path(book_friend)

      expect(response.body).to include("FRIEND_ONLY_PUBLIC_JJAEK", "FRIEND_ONLY_BOOK_JJAEK")
      expect(page_text).to include("Book Friend님이 책을 서재에 담았습니다.")
    end

    it "shows only public Jjaeks from a follow-only user in the home feed" do
      viewer.active_follows.create!(followee:)
      followee.jjaeks.create!(content: "FOLLOW_ONLY_PUBLIC_JJAEK", visibility: :public_jjaek)
      followee.jjaeks.create!(book: followee_book, content: "FOLLOW_ONLY_BOOK_FRIENDS_JJAEK", visibility: :book_friends)
      BookActivity.create!(user: followee, book: followee_book, bookshelf_entry: followee.bookshelf_entries.find_or_create_by!(book: followee_book), action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).to include("FOLLOW_ONLY_PUBLIC_JJAEK")
      expect(response.body).not_to include("FOLLOW_ONLY_BOOK_FRIENDS_JJAEK", "소식받기 활동 책")
    end

    it "shows public and book-friends Jjaeks and BookActivity from a followed book friend" do
      viewer.active_follows.create!(followee: book_friend)
      BookFriendship.create!(requester: viewer, addressee: book_friend, status: :accepted)
      book_friend.jjaeks.create!(content: "FOLLOWED_FRIEND_PUBLIC_JJAEK", visibility: :public_jjaek)
      book_friend.jjaeks.create!(book: friend_book, content: "FOLLOWED_FRIEND_BOOK_JJAEK", visibility: :book_friends)
      BookActivity.create!(user: book_friend, book: friend_book, bookshelf_entry: book_friend.bookshelf_entries.find_or_create_by!(book: friend_book), action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).to include("FOLLOWED_FRIEND_PUBLIC_JJAEK", "FOLLOWED_FRIEND_BOOK_JJAEK")
      expect(page_text).to include("Book Friend님이 책을 서재에 담았습니다.")
    end

    it "does not show a stranger's Jjaeks or BookActivity in the home feed" do
      stranger.jjaeks.create!(content: "STRANGER_PUBLIC_JJAEK", visibility: :public_jjaek)
      stranger.jjaeks.create!(book: stranger_book, content: "STRANGER_BOOK_FRIENDS_JJAEK", visibility: :book_friends)
      BookActivity.create!(user: stranger, book: stranger_book, bookshelf_entry: stranger.bookshelf_entries.find_or_create_by!(book: stranger_book), action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).not_to include("STRANGER_PUBLIC_JJAEK", "STRANGER_BOOK_FRIENDS_JJAEK", "낯선 활동 책")
    end

    it "still shows existing Jjaeks in the home feed" do
      jjaek = viewer.jjaeks.create!(content: "HOME_FEED_EXISTING_JJAEK", visibility: :public_jjaek)
      sign_in viewer

      get root_path

      expect(response.body).to include("HOME_FEED_EXISTING_JJAEK")
      expect(response.body).to include(%(id="comments_panel_home_jjaek_#{jjaek.id}"))
      expect(response.body).to include(%(href="/jjaeks/#{jjaek.id}/comments?comments_context=home"))
      expect(response.body).to include(%(data-turbo-stream="true"))
      expect(page_text).to include(I18n.t("comments.actions.view_inline"))
      expect(response.body).to include(%(href="#{ERB::Util.html_escape(jjaek_path(jjaek, return_to: root_path, anchor: "comments_panel_jjaek_#{jjaek.id}"))}"))
    end

    it "keeps group jjaeks out of the people-based home feed" do
      group_admin = User.create!(name: "Group admin", email: "home-group-admin@example.com", password: "password123!")
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Home excluded group", group_type: :private_group)
      group.group_memberships.create!(user: viewer, status: :active)
      group_book = Book.create!(title: "HOME EXCLUDED GROUP BOOK", authors_text: "Author")
      group.jjaeks.create!(user: group_admin, content: "HOME EXCLUDED GROUP JJAEK")
      group.jjaeks.create!(user: group_admin, book: group_book, content: "HOME EXCLUDED GROUP BOOK JJAEK")
      hidden_group_jjaek = group.jjaeks.create!(user: viewer, content: "HOME EXCLUDED HIDDEN GROUP JJAEK")
      Jjaeks::Hide.new(hidden_group_jjaek, actor: group_admin, public_reason: "other").call!
      personal_jjaek = viewer.jjaeks.create!(content: "HOME ELIGIBLE PERSONAL JJAEK", visibility: :public_jjaek)
      sign_in viewer

      get root_path

      expect(response.body).to include(personal_jjaek.content)
      expect(response.body).not_to include(
        "HOME EXCLUDED GROUP JJAEK",
        "HOME EXCLUDED GROUP BOOK JJAEK",
        "HOME EXCLUDED GROUP BOOK",
        "동아리 관리자에 의해 숨겨진 짹입니다."
      )
    end

    it "orders Jjaeks and BookActivities together by created_at" do
      old_jjaek = viewer.jjaeks.create!(
        content: "HOME_FEED_OLD_JJAEK",
        visibility: :public_jjaek,
        created_at: 3.hours.ago
      )
      middle_activity = BookActivity.create!(
        user: viewer,
        book: viewer_book,
        bookshelf_entry: viewer.bookshelf_entries.find_or_create_by!(book: viewer_book),
        action: :added_to_shelf,
        created_at: 2.hours.ago
      )
      new_jjaek = viewer.jjaeks.create!(
        content: "HOME_FEED_NEW_JJAEK",
        visibility: :public_jjaek,
        created_at: 1.hour.ago
      )
      sign_in viewer

      get root_path

      new_index = page_text.index(new_jjaek.content)
      activity_index = page_text.index("Viewer님이 책을 서재에 담았습니다.")
      old_index = page_text.index(old_jjaek.content)

      expect(new_index).to be < activity_index
      expect(activity_index).to be < old_index
    end
  end

  def page_text
    ActionView::Base.full_sanitizer.sanitize(response.body)
  end
end
