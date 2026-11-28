require "rails_helper"

RSpec.describe "Requotes", type: :request do
  let(:viewer) { User.create!(name: "Reader", email: "requote-request-reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:original_author) { User.create!(name: "Original", email: "requote-request-original@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "Requote list book", authors_text: "Author") }
  let(:friendship) { BookFriendship.create!(requester: viewer, addressee: original_author, status: :accepted) }
  let(:original) { create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: original_author, content: "REQUEST_ORIGINAL_BOOK_FRIENDS_SOURCE", visibility: :book_friends) }
  let(:viewer_requote) { create_legacy_book_requote(user: viewer, book:, content: "REQUEST_VIEWER_REQUOTE_BODY", quoted_jjaek: original, visibility: :private_jjaek) }

  before do
    friendship
  end

  describe "unified requote action" do
    it "shows the count and icon without avatars on home, profile, book, and detail cards" do
      source = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: original_author, content: "COUNT_LINK_SOURCE")
      users = 6.times.map do |index|
        User.create!(name: "Requoter #{index}", email: "avatar-requoter-#{index}@example.com", password: "password123!")
      end
      created_at = 1.hour.ago
      users.each_with_index do |user, index|
        user.jjaeks.create!(quoted_jjaek: source, content: "Opinion #{index}", created_at: created_at + index.minutes)
      end
      group = Group.create!(lifecycle_status: :active, group_admin: users.first, name: "Avatar readers", group_type: :public_group)
      users.first.jjaeks.create!(group:, quoted_jjaek: source, content: "Latest duplicate", created_at: created_at + 5.minutes)
      other_source = original_author.jjaeks.create!(content: "OTHER_COUNT_LINK_SOURCE")
      users.second.jjaeks.create!(quoted_jjaek: other_source, content: "Another source")
      empty_source = original_author.jjaeks.create!(content: "NO_REQUOTES_SOURCE")
      sign_in original_author

      [ root_path, user_path(original_author), book_path(book), jjaek_path(source) ].each do |path|
        get path

        page = Nokogiri::HTML(response.body)
        card = page.at_css("article#jjaek_#{source.id}")
        menu = card.at_css("details[data-controller='requote-menu']")
        summary = menu.at_css("summary")
        expect(summary.text.strip).to eq(I18n.t("jjaeks.meta.requotes", count: 7))
        expect(summary.at_css("svg[aria-hidden='true']")).to be_present
        expect(menu.at_css("img")).to be_nil
        expect(menu.css("a").map { |link| link.text.strip }).to eq([
          I18n.t("requotes.actions.view_count", count: 7), I18n.t("jjaeks.actions.requote_to_feed")
        ])
        expect(menu.at_css("a")["href"]).to eq(jjaek_requotes_path(source))
        expect(card.css("a[href='#{jjaek_requotes_path(source)}']").size).to eq(1)
        if path == root_path
          other_link = page.at_css("article#jjaek_#{other_source.id} a[href='#{jjaek_requotes_path(other_source)}']")
          expect(other_link.text.strip).to eq(I18n.t("requotes.actions.view_count", count: 1))
          expect(other_link.ancestors("details").first.at_css("summary").text.strip).to eq(I18n.t("jjaeks.meta.requotes", count: 1))
          empty_card = page.at_css("article#jjaek_#{empty_source.id}")
          expect(empty_card.at_css("a[href='#{jjaek_requotes_path(empty_source)}']")).to be_nil
        end
      end
    end

    it "keeps counts and list entries scoped to what the viewer can currently read" do
      source = original_author.jjaeks.create!(content: "AVATAR_VISIBILITY_SOURCE")
      public_user = User.create!(name: "Public requoter", email: "avatar-public@example.com", password: "password123!")
      friend_user = User.create!(name: "Friend requoter", email: "avatar-friend@example.com", password: "password123!")
      private_user = User.create!(name: "Private requoter", email: "avatar-private@example.com", password: "password123!")
      public_requote = public_user.jjaeks.create!(quoted_jjaek: source, content: "Public opinion")
      friend_user.jjaeks.create!(quoted_jjaek: source, content: "Friends opinion", visibility: :book_friends)
      private_user.jjaeks.create!(quoted_jjaek: source, content: "Private opinion", visibility: :private_jjaek)
      own_requote = viewer.jjaeks.create!(quoted_jjaek: source, content: "My private opinion", visibility: :private_jjaek)
      connection = BookFriendship.create!(requester: viewer, addressee: friend_user, status: :accepted)
      sign_in viewer

      get jjaek_path(source)
      link = Nokogiri::HTML(response.body).at_css("article#jjaek_#{source.id} a[href='#{jjaek_requotes_path(source)}']")
      expect(link.text.strip).to eq(I18n.t("jjaeks.meta.requotes", count: 3))
      get jjaek_requotes_path(source)
      expect(response.body).to include("My private opinion", "Public opinion", "Friends opinion")
      expect(response.body).not_to include("Private opinion")

      connection.destroy!
      public_requote.update!(hidden_at: Time.current)
      get jjaek_path(source)
      link = Nokogiri::HTML(response.body).at_css("article#jjaek_#{source.id} a[href='#{jjaek_requotes_path(source)}']")
      expect(link.text.strip).to eq(I18n.t("jjaeks.meta.requotes", count: 1))
      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: source.id))
      get jjaek_requotes_path(source)
      expect(response.body).to include("My private opinion")
      expect(response.body).not_to include("Public opinion", "Friends opinion", "Private opinion")

      own_requote.comments.create!(user: viewer, content: "Preserve tombstone")
      own_requote.destroy_or_tombstone!
      get jjaek_requotes_path(source)
      tombstone = Nokogiri::HTML(response.body).at_css("article#jjaek_#{own_requote.id}")
      expect(tombstone.text).to include(I18n.t("jjaeks.labels.deleted"))
      expect(response.body).not_to include("My private opinion")
    end
  end

  describe "GET /jjaeks/:jjaek_id/requotes" do
    it "redirects a missing personal source home instead of returning 404, like an inaccessible source" do
      source = original
      source_content = source.content
      friendship.destroy!
      missing_source_id = Jjaek.maximum(:id) + 1
      sign_in viewer

      get jjaek_requotes_path(missing_source_id)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
      expect(response.body).not_to include(source_content, original_author.name)

      get jjaek_requotes_path(source)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
      expect(response.body).not_to include(source_content, original_author.name)
    end

    it "shows an author a limited approval-group card alongside a readable requote in standalone HTML" do
      source = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: original_author, content: "AUTHOR_BOOK_SOURCE")
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Approval readers", group_type: :approval_group)
      readable = viewer.jjaeks.create!(quoted_jjaek: source, content: "READABLE_OPINION")
      readable.comments.create!(user: viewer, content: "Comment")
      readable.comments.create!(user: viewer, content: "Hidden comment", hidden_at: Time.current)
      readable.likes.create!(user: viewer)
      readable.likes.create!(user: original_author)
      restricted = viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "PRIVATE_GROUP_OPINION")
      sign_in original_author

      get jjaek_path(source)
      source_card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{source.id}")
      expect(source_card.text).to include(I18n.t("jjaeks.meta.requotes", count: 2))

      get user_path(original_author)
      profile_card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{source.id}")
      expect(profile_card.text).to include(I18n.t("jjaeks.meta.requotes", count: 2))

      [ {}, { "Accept" => "text/vnd.turbo-stream.html" } ].each do |headers|
        get jjaek_requotes_path(source), headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/html")
        page = Nokogiri::HTML(response.body)
        expect(page.css("turbo-stream")).to be_empty
        limited_card = page.at_css("article[data-restricted-requote]")
        readable_card = page.at_css("article#jjaek_#{readable.id}")
        expect(readable_card).to be_present
        expect(readable_card.text).to include(I18n.t("jjaeks.meta.comments", count: 2))
        like = readable_card.at_css("#like_action_jjaek_#{readable.id} button")
        expect(like["aria-description"]).to eq(I18n.t("jjaeks.meta.likes", count: 2))
        expect(like["aria-pressed"]).to eq("true")
        expect(limited_card.text).to include(
          I18n.t("requotes.restricted.context_html", author_name: viewer.name,
                  source_author_name: original_author.name, source_kind: "짹", group_name: group.name),
          I18n.t("requotes.restricted.notice"),
          I18n.t("jjaeks.meta.created_at", time: I18n.l(restricted.created_at, format: :short))
        )
        expect(limited_card["class"]).to include("rounded-3xl border border-stone-200 bg-white p-5 shadow-sm")
        expect(limited_card.at_css("img.h-10.w-10")["alt"]).to eq(viewer.name)
        expect(limited_card.css("a").map { |link| link["href"] }).to contain_exactly(
          user_path(viewer), user_path(original_author), group_path(group)
        )
        expect(limited_card.text).not_to include(restricted.content)
        expect(limited_card.at_css("button, form")).to be_nil
        expect(limited_card.at_css("a[href='#{jjaek_path(restricted)}']")).to be_nil
        expect(response.body).not_to include(jjaek_path(restricted), restricted.content)
      end

      membership = group.group_memberships.create!(user: original_author, status: :active)
      get jjaek_path(source)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 2))
      get jjaek_requotes_path(source)
      expect(response.body).to include(restricted.content)
      expect(Nokogiri::HTML(response.body).css("article[data-restricted-requote]")).to be_empty

      membership.destroy!
      get jjaek_path(source)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 2))
      get jjaek_requotes_path(source)
      expect(Nokogiri::HTML(response.body).css("article[data-restricted-requote]").size).to eq(1)
      expect(response.body).not_to include(restricted.content)

      readable.update!(hidden_at: Time.current)
      get jjaek_path(source)
      source_card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{source.id}")
      expect(source_card.text).not_to include(viewer.name)
      expect(source_card.at_css("a[href='#{user_path(viewer)}']")).to be_nil
      expect(source_card.at_css("img[alt='#{viewer.name}']")).to be_nil
      link = source_card.at_css("a[href='#{jjaek_requotes_path(source)}']")
      expect(link.text.strip).to eq(I18n.t("requotes.actions.view_count", count: 1))
      expect(link.at_css("img")).to be_nil
    end

    it "counts a private-group requote for its source author without revealing its identity" do
      source = original_author.jjaeks.create!(content: "PUBLIC_AUTHOR_SOURCE")
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "SECRET_DESTINATION", group_type: :private_group)
      restricted = viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "SECRET_OPINION")
      sign_in original_author

      get jjaek_path(source)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1))
      source_card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{source.id}")
      expect(source_card.text).not_to include(viewer.name)
      expect(source_card.at_css("a[href='#{user_path(viewer)}']")).to be_nil
      expect(source_card.at_css("img[alt='#{viewer.name}']")).to be_nil
      link = source_card.at_css("a[href='#{jjaek_requotes_path(source)}']")
      expect(link.text.strip).to eq(I18n.t("requotes.actions.view_count", count: 1))
      expect(link.at_css("img")).to be_nil
      get jjaek_requotes_path(source)
      limited_card = Nokogiri::HTML(response.body).at_css("article[data-restricted-requote]")
      expect(limited_card.text).to include(I18n.t("requotes.restricted.notice"))
      expect(limited_card.text).not_to include(group.name, viewer.name, restricted.content)
      expect(limited_card.text).not_to include(I18n.t("jjaeks.meta.created_at", time: I18n.l(restricted.created_at, format: :short)))
      expect(limited_card.at_css("svg[aria-hidden='true']")).to be_present
      expect(limited_card.at_css("a, button, form, img")).to be_nil
      expect(response.body).not_to include(group.name, viewer.name, restricted.content,
                                           group_path(group), jjaek_path(restricted))
    end

    it "does not reveal a restricted group requote or its count to another reader" do
      source = original_author.jjaeks.create!(content: "PUBLIC_SOURCE_FOR_OTHERS")
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "APPROVAL_DESTINATION", group_type: :approval_group)
      restricted = viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "INACCESSIBLE_OPINION")
      other_reader = User.create!(name: "Other reader", email: "other-requote-reader@example.com", password: "password123!")
      sign_in other_reader

      get jjaek_path(source)
      expect(response.body).not_to include(jjaek_requotes_path(source), I18n.t("jjaeks.meta.requotes", count: 1))
      get jjaek_requotes_path(source)
      expect(response.body).to include(I18n.t("requotes.index.empty"))
      expect(response.body).not_to include(group.name, viewer.name, restricted.content)
    end

    it "omits hidden and deleted group requotes from an author's limited overview" do
      source = original_author.jjaeks.create!(content: "SOURCE_WITH_MODERATED_REQUOTES")
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Approval group", group_type: :approval_group)
      restricted = viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "MODERATED_OPINION")
      sign_in original_author

      restricted.update!(hidden_at: Time.current)
      get jjaek_path(source)
      expect(response.body).not_to include(jjaek_requotes_path(source))
      get jjaek_requotes_path(source)
      expect(Nokogiri::HTML(response.body).css("article[data-restricted-requote]")).to be_empty

      restricted.update!(hidden_at: nil)
      restricted.comments.create!(user: viewer, content: "Keep the quote as a tombstone")
      restricted.destroy_or_tombstone!
      get jjaek_path(source)
      expect(response.body).not_to include(jjaek_requotes_path(source))
      get jjaek_requotes_path(source)
      expect(Nokogiri::HTML(response.body).css("article[data-restricted-requote]")).to be_empty

      source.destroy!
      expect(restricted.reload.quoted_jjaek_id).to be_nil
    end

    it "shows the visible requote list for an active public group original" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Public requote list", group_type: :public_group)
      group_jjaek = original_author.jjaeks.create!(group:, content: "PUBLIC_GROUP_REQUOTE_LIST_SOURCE")
      personal_requote = original_author.jjaeks.create!(quoted_jjaek: group_jjaek, content: "PUBLIC_GROUP_PERSONAL_REQUOTE")
      group_requote = original_author.jjaeks.create!(group:, quoted_jjaek: group_jjaek, content: "PUBLIC_GROUP_INTERNAL_REQUOTE")
      sign_in viewer

      get group_path(group)
      source_card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{group_jjaek.id}")
      expect(source_card.text).to include(I18n.t("jjaeks.meta.requotes", count: 2))
      link = source_card.at_css("a[href='#{jjaek_requotes_path(group_jjaek)}']")
      expect(link.text.strip).to eq(I18n.t("requotes.actions.view_count", count: 2))
      expect(link.at_css("img")).to be_nil

      get jjaek_requotes_path(group_jjaek)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(group_jjaek.content, personal_requote.content, group_requote.content)

      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      get jjaek_requotes_path(group_jjaek)
      expect(response).to redirect_to(root_path)
      expect(response.body).not_to include(personal_requote.content, group_requote.content, group.name)
    end

    it "counts only readable personal and group requotes of a public personal original" do
      source = original_author.jjaeks.create!(content: "PUBLIC_PERSONAL_SOURCE")
      public_group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "PUBLIC_DESTINATION", group_type: :public_group)
      private_group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "PRIVATE_DESTINATION", group_type: :private_group)
      personal_requote = viewer.jjaeks.create!(quoted_jjaek: source, content: "PERSONAL_REQUOTE")
      public_group_requote = viewer.jjaeks.create!(group: public_group, quoted_jjaek: source, content: "PUBLIC_GROUP_REQUOTE")
      hidden_group_requote = original_author.jjaeks.create!(group: private_group, quoted_jjaek: source, content: "PRIVATE_GROUP_REQUOTE")
      sign_in viewer

      get jjaek_path(source)
      source_card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{source.id}")
      expect(source_card.text).to include(I18n.t("jjaeks.meta.requotes", count: 2))
      expect(source_card.at_css("a[href='#{jjaek_requotes_path(source)}']")).to be_present
      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: source.id))

      get jjaek_requotes_path(source)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(personal_requote.content, public_group_requote.content)
      expect(response.body).not_to include(hidden_group_requote.content, private_group.name)

      membership = private_group.group_memberships.create!(user: viewer, status: :active)
      get jjaek_path(source)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 3))
      get jjaek_requotes_path(source)
      expect(response.body).to include(hidden_group_requote.content, private_group.name)

      membership.destroy!
      get jjaek_path(source)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 2))
      get jjaek_requotes_path(source)
      expect(response.body).not_to include(hidden_group_requote.content, private_group.name)
    end

    it "shows an internal requote to members of approval and private groups, then removes access" do
      %i[approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "SECRET_#{group_type}", group_type:)
        membership = group.group_memberships.create!(user: viewer, status: :active)
        source = original_author.jjaeks.create!(group:, content: "SOURCE_#{group_type}")
        requote = viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "REQUOTE_#{group_type}")
        sign_in viewer

        get jjaek_path(source)
        expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1))
        expect(response.body).to include(jjaek_requotes_path(source))
        get jjaek_requotes_path(source)
        expect(response.body).to include(requote.content)

        membership.destroy!
        get jjaek_requotes_path(source)
        expect(response).to redirect_to(root_path)
        expect(response.body).not_to include(source.content, requote.content, group.name)
        get jjaek_path(source)
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(I18n.t("jjaeks.meta.requotes", count: 1), requote.content, group.name)
      end
    end

    it "keeps a member's list readable after the source group becomes inactive" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Inactive readers", group_type: :private_group)
      group.group_memberships.create!(user: viewer, status: :active)
      source = original_author.jjaeks.create!(group:, content: "INACTIVE_GROUP_SOURCE")
      requote = viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "INACTIVE_GROUP_REQUOTE")
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      sign_in viewer

      get jjaek_path(source)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1), jjaek_requotes_path(source))
      expect(response.body).not_to include(new_group_jjaek_path(group, quoted_jjaek_id: source.id))

      get jjaek_requotes_path(source)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(requote.content)
    end

    it "denies a hidden source list and detaches requotes when a source is deleted" do
      source = original_author.jjaeks.create!(content: "SOURCE_TO_REMOVE")
      requote = viewer.jjaeks.create!(quoted_jjaek: source, content: "REQUOTE_TO_KEEP")
      sign_in viewer

      source.update!(hidden_at: Time.current)
      get jjaek_requotes_path(source)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
      expect(response.body).not_to include(requote.content)

      source.update!(hidden_at: nil)
      source.comments.create!(user: viewer, content: "Keep the source as a tombstone")
      source.destroy_or_tombstone!
      expect(requote.reload.quoted_jjaek_id).to be_nil

      get jjaek_requotes_path(source)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
      get jjaek_path(source)
      expect(response.body).not_to include(jjaek_requotes_path(source))
    end

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

    it "renders the standalone list with the same read permissions when requested with a stream Accept header" do
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

      expect(response.media_type).to eq("text/html")
      expect(response.body).not_to include("requotes_panel_jjaek_#{original.id}", "<turbo-stream")
      expect(response.body).to include(visible_book_friends_requote.content)
      expect(response.body).to include(viewer_requote.content)
      expect(response.body).not_to include("HIDDEN_TURBO_REQUOTE_IN_LIST")
      expect(response.body).to include(I18n.t("requotes.index.description"))
    end

    it "allows a private original's owner to view an existing readable requote" do
      private_original = viewer.jjaeks.create!(content: "PRIVATE_REQUOTE_LIST_SOURCE")
      existing_requote = viewer.jjaeks.create!(quoted_jjaek: private_original, content: "OWNER_PRIVATE_REQUOTE", visibility: :private_jjaek)
      private_original.update!(visibility: :private_jjaek)
      sign_in viewer

      get jjaek_path(private_original)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1), jjaek_requotes_path(private_original))
      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: private_original.id))

      get jjaek_requotes_path(private_original)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(existing_requote.content)
    end

    it "does not allow requote list access for a requote" do
      sign_in viewer
      viewer_requote

      get jjaek_requotes_path(viewer_requote)

      expect(response).to redirect_to(root_path)
    end
  end
end
