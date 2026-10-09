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
    it "shows an author a limited approval-group card alongside a readable requote in HTML and Turbo" do
      source = original_author.jjaeks.create!(book:, content: "AUTHOR_BOOK_SOURCE")
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Approval readers", group_type: :approval_group)
      readable = viewer.jjaeks.create!(quoted_jjaek: source, content: "READABLE_OPINION")
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
        expect(response.media_type).to eq(headers.empty? ? "text/html" : "text/vnd.turbo-stream.html")
        page = Nokogiri::HTML(response.body)
        limited_card = page.at_css("article[data-restricted-requote]")
        expect(page.at_css("article#jjaek_#{readable.id}")).to be_present
        expect(limited_card.text).to include(
          I18n.t("requotes.restricted.context_html", author_name: viewer.name,
                  source_author_name: original_author.name, source_kind: "책짹", group_name: group.name),
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
    end

    it "counts a private-group requote for its source author without revealing its identity" do
      source = original_author.jjaeks.create!(content: "PUBLIC_AUTHOR_SOURCE")
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "SECRET_DESTINATION", group_type: :private_group)
      restricted = viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "SECRET_OPINION")
      sign_in original_author

      get jjaek_path(source)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1))
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
      expect(source_card.at_css("a[href='#{jjaek_requotes_path(group_jjaek)}']")).to be_present

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
      expect(response.body).not_to include(requote.content)

      source.update!(hidden_at: nil)
      source.comments.create!(user: viewer, content: "Keep the source as a tombstone")
      source.destroy_or_tombstone!
      expect(requote.reload.quoted_jjaek_id).to be_nil

      get jjaek_requotes_path(source)
      expect(response).to redirect_to(root_path)
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
