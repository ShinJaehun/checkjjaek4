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

    it "rerenders the book page with only original book jjaeks when a book-linked jjaek is invalid" do
      viewer.bookshelf_entries.create!(book:)
      original_book_jjaek = original_author.jjaeks.create!(book:, content: "VISIBLE_BOOK_ORIGINAL", visibility: :public_jjaek)
      hidden_requote = viewer.jjaeks.create!(book:, content: "HIDDEN_BOOK_REQUOTE", quoted_jjaek: original_book_jjaek, visibility: :private_jjaek)
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            book_id: book.id,
            content: "",
            visibility: :public_jjaek
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(original_book_jjaek.content)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1))
      expect(response.body).not_to include(hidden_requote.content)
      expect(response.body).to include('name="jjaek[content]"')
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

    it "redirects stale requote submissions without creating a regular jjaek" do
      hard_deleted_source = original_author.jjaeks.create!(content: "HARD_DELETED_REQUOTE_SOURCE")
      hard_deleted_source_id = hard_deleted_source.id
      hard_deleted_source.destroy!
      out_of_scope_source = original
      friendship.destroy!
      sign_in viewer
      jjaek_count = Jjaek.count
      notification_count = Notification.count

      post jjaeks_path, params: {
        jjaek: {
          quoted_jjaek_id: hard_deleted_source_id,
          content: "HARD_DELETED_SOURCE_REQUOTE",
          visibility: :public_jjaek
        }
      }
      hard_deleted_response = [ response.status, response.location, flash[:alert] ]

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.requote_source_unavailable"))
      expect(Jjaek.count).to eq(jjaek_count)
      expect(Notification.count).to eq(notification_count)

      post jjaeks_path, params: {
        jjaek: {
          quoted_jjaek_id: out_of_scope_source.id,
          content: "OUT_OF_SCOPE_SOURCE_REQUOTE",
          visibility: :public_jjaek
        }
      }

      expect([ response.status, response.location, flash[:alert] ]).to eq(hard_deleted_response)
      expect(Jjaek.count).to eq(jjaek_count)
      expect(Notification.count).to eq(notification_count)
      expect(Jjaek.where(content: %w[HARD_DELETED_SOURCE_REQUOTE OUT_OF_SCOPE_SOURCE_REQUOTE])).to be_empty
    end

    it "creates a personal requote from an active public group original for a non-member" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Public requote source", group_type: :public_group)
      group_jjaek = original_author.jjaeks.create!(group:, book:, content: "PUBLIC_GROUP_REQUOTE_SOURCE")
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            quoted_jjaek_id: group_jjaek.id,
            content: "PUBLIC_GROUP_PERSONAL_REQUOTE",
            visibility: :public_jjaek
          }
        }
      }.to change(Jjaek, :count).by(1)

      created_jjaek = Jjaek.last
      expect(created_jjaek.group_id).to be_nil
      expect(created_jjaek.quoted_jjaek_id).to eq(group_jjaek.id)
    end

    it "rejects direct requote creation from approval and private group originals" do
      sign_in viewer

      %i[approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Blocked #{group_type}", group_type:)
        group.group_memberships.create!(user: viewer, status: :active)
        group_jjaek = original_author.jjaeks.create!(group:, content: "BLOCKED_GROUP_REQUOTE_SOURCE")

        expect {
          post jjaeks_path, params: { jjaek: { quoted_jjaek_id: group_jjaek.id, content: "BLOCKED_REQUOTE" } }
        }.not_to change(Jjaek, :count)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
      end
    end

    it "rejects direct requote creation from an inactive public group original" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Inactive public source", group_type: :public_group)
      group.group_memberships.create!(user: viewer, status: :active)
      group_jjaek = original_author.jjaeks.create!(group:, content: "INACTIVE_GROUP_REQUOTE_SOURCE")
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      sign_in viewer

      expect {
        post jjaeks_path, params: { jjaek: { quoted_jjaek_id: group_jjaek.id, content: "BLOCKED_INACTIVE_REQUOTE" } }
      }.not_to change(Jjaek, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
    end

    it "does not create a duplicate requote for the same user and original" do
      sign_in viewer
      requote

      expect {
        post jjaeks_path, params: {
          jjaek: {
            quoted_jjaek_id: original.id,
            content: "REQUEST_DUPLICATE_REQUOTE_BODY",
            visibility: :private_jjaek
          }
        }
      }.not_to change(Jjaek, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "creates a notification when writing a profile-context jjaek on another user's profile" do
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            target_user_id: original_author.id,
            content: "PROFILE_NOTIFICATION_BODY",
            visibility: :book_friends
          }
        }
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification).to be_profile_jjaek_created
      expect(notification.recipient).to eq(original_author)
      expect(notification.actor).to eq(viewer)
      expect(notification.notifiable).to eq(Jjaek.last)
    end

    it "does not create a self-targeted profile-context jjaek or notification" do
      sign_in viewer
      jjaek_count = Jjaek.count
      notification_count = Notification.count

      post jjaeks_path, params: {
        jjaek: {
          target_user_id: viewer.id,
          content: "SELF_PROFILE_NOTIFICATION_BODY",
          visibility: :private_jjaek
        }
      }

      expect(Jjaek.count).to eq(jjaek_count)
      expect(Notification.count).to eq(notification_count)
      expect(response).to redirect_to(root_path)
    end

    it "creates a notification when another user requotes your jjaek" do
      sign_in viewer
      original

      expect {
        post jjaeks_path, params: {
          jjaek: {
            quoted_jjaek_id: original.id,
            content: "REQUEST_NEW_REQUOTE_BODY",
            visibility: :book_friends
          }
        }
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification).to be_requote_created
      expect(notification.recipient).to eq(original_author)
      expect(notification.actor).to eq(viewer)
      expect(notification.notifiable).to eq(Jjaek.last)
    end

    it "does not create a notification when requoting your own jjaek" do
      own_original = viewer.jjaeks.create!(content: "OWN_REQUOTE_SOURCE", visibility: :public_jjaek)
      sign_in viewer

      expect {
        post jjaeks_path, params: {
          jjaek: {
            quoted_jjaek_id: own_original.id,
            content: "SELF_REQUOTE_NOTIFICATION_BODY",
            visibility: :public_jjaek
          }
        }
      }.not_to change(Notification, :count)
    end

    it "does not create a notification for a requote the recipient cannot see" do
      sign_in viewer
      original

      expect {
        post jjaeks_path, params: {
          jjaek: {
            quoted_jjaek_id: original.id,
            content: "PRIVATE_REQUOTE_NOTIFICATION_BODY",
            visibility: :private_jjaek
          }
        }
      }.not_to change(Notification, :count)
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
      expect(response.body).to include("ReJjaek request book")
      expect(response.body).to include("Author")
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

  describe "editing Jjaeks" do
    it "redirects a stale edit page with the generic Jjaek alert" do
      stale_jjaek = viewer.jjaeks.create!(content: "STALE_EDIT_SOURCE")
      stale_jjaek_id = stale_jjaek.id
      stale_jjaek.destroy!
      sign_in viewer

      get edit_jjaek_path(stale_jjaek_id)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
    end

    it "redirects a stale update without changing Jjaeks or notifications" do
      stale_jjaek = viewer.jjaeks.create!(content: "STALE_UPDATE_SOURCE")
      stale_jjaek_id = stale_jjaek.id
      stale_jjaek.destroy!
      sign_in viewer
      jjaek_count = Jjaek.count
      jjaek_state = Jjaek.order(:id).pluck(:id, :content, :visibility, :updated_at)
      notification_count = Notification.count

      patch jjaek_path(stale_jjaek_id), params: {
        jjaek: { content: "SHOULD_NOT_BE_CREATED", visibility: :public_jjaek }
      }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
      expect(Jjaek.count).to eq(jjaek_count)
      expect(Jjaek.order(:id).pluck(:id, :content, :visibility, :updated_at)).to eq(jjaek_state)
      expect(Jjaek.exists?(stale_jjaek_id)).to be(false)
      expect(Notification.count).to eq(notification_count)
    end

    it "keeps Pundit authorization for visible Jjaeks owned by another user" do
      visible_jjaek = original_author.jjaeks.create!(content: "VISIBLE_UNEDITABLE_TARGET")
      sign_in viewer

      get edit_jjaek_path(visible_jjaek)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))

      patch jjaek_path(visible_jjaek), params: { jjaek: { content: "UNAUTHORIZED_UPDATE" } }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
      expect(visible_jjaek.reload.content).to eq("VISIBLE_UNEDITABLE_TARGET")
    end

    it "updates an editable live Jjaek normally" do
      editable_jjaek = viewer.jjaeks.create!(content: "BEFORE_NORMAL_UPDATE")
      sign_in viewer

      patch jjaek_path(editable_jjaek), params: {
        jjaek: { content: "AFTER_NORMAL_UPDATE", visibility: :book_friends }
      }

      expect(response).to redirect_to(jjaek_path(editable_jjaek))
      expect(editable_jjaek.reload).to have_attributes(
        content: "AFTER_NORMAL_UPDATE",
        visibility: "book_friends"
      )
    end
  end

  describe "destroying Jjaeks" do
    it "redirects a stale hard-deleted Jjaek without changing other records" do
      remaining_jjaek = viewer.jjaeks.create!(content: "REMAINING_JJAEK")
      stale_jjaek = viewer.jjaeks.create!(content: "STALE_DESTROY_SOURCE")
      stale_jjaek_id = stale_jjaek.id
      stale_jjaek.destroy!
      sign_in viewer
      jjaek_count = Jjaek.count
      like_count = Like.count
      comment_count = Comment.count
      notification_count = Notification.count
      jjaek_state = Jjaek.order(:id).pluck(:id, :content, :deleted_at, :updated_at)

      delete jjaek_path(stale_jjaek_id)

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
      expect(Jjaek.count).to eq(jjaek_count)
      expect(Like.count).to eq(like_count)
      expect(Comment.count).to eq(comment_count)
      expect(Notification.count).to eq(notification_count)
      expect(Jjaek.order(:id).pluck(:id, :content, :deleted_at, :updated_at)).to eq(jjaek_state)
      expect(remaining_jjaek.reload.content).to eq("REMAINING_JJAEK")
    end

    it "keeps Pundit authorization for another user's live Jjaek" do
      other_jjaek = original_author.jjaeks.create!(content: "OTHER_LIVE_JJAEK")
      updated_at = other_jjaek.updated_at
      sign_in viewer

      delete jjaek_path(other_jjaek)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
      expect(flash[:alert]).not_to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
      expect(other_jjaek.reload.content).to eq("OTHER_LIVE_JJAEK")
      expect(other_jjaek.updated_at).to eq(updated_at)
    end

    it "keeps Pundit authorization for an existing deleted tombstone" do
      tombstone = viewer.jjaeks.create!(content: "BEFORE_TOMBSTONE")
      preserved_comment = tombstone.comments.create!(user: original_author, content: "PRESERVED_COMMENT")
      tombstone.destroy_or_tombstone!
      tombstone.reload
      tombstone_state = tombstone.attributes.slice("content", "deleted_at", "updated_at")
      sign_in viewer
      jjaek_count = Jjaek.count
      comment_count = Comment.count

      delete jjaek_path(tombstone)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
      expect(flash[:alert]).not_to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
      expect(tombstone.reload).to be_deleted
      expect(tombstone.attributes.slice("content", "deleted_at", "updated_at")).to eq(tombstone_state)
      expect(Comment.exists?(preserved_comment.id)).to be(true)
      expect(Jjaek.count).to eq(jjaek_count)
      expect(Comment.count).to eq(comment_count)
    end

    it "hard-deletes a live own Jjaek without comments" do
      own_jjaek = viewer.jjaeks.create!(content: "LIVE_DESTROY_SOURCE")
      own_jjaek_id = own_jjaek.id
      sign_in viewer

      expect {
        delete jjaek_path(own_jjaek)
      }.to change(Jjaek, :count).by(-1)

      expect(Jjaek.exists?(own_jjaek_id)).to be(false)
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq(I18n.t("jjaeks.notices.destroyed"))
    end
  end

  describe "GET /jjaeks/:id" do
    it "keeps missing and inaccessible Group Jjaek show requests as not found" do
      private_group = Group.create!(
        lifecycle_status: :active,
        group_admin: original_author,
        name: "Inaccessible show group",
        group_type: :private_group
      )
      inaccessible_jjaek = original_author.jjaeks.create!(group: private_group, content: "INACCESSIBLE_SHOW_TARGET")
      missing_jjaek_id = Jjaek.maximum(:id).to_i + 1
      sign_in viewer

      get jjaek_path(missing_jjaek_id)
      expect(response).to have_http_status(:not_found)

      sign_in viewer
      get jjaek_path(inaccessible_jjaek)
      expect(response).to have_http_status(:not_found)
    end

    it "shows the requote action on an active public group original for a non-member" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Public detail source", group_type: :public_group)
      group_jjaek = original_author.jjaeks.create!(group:, content: "PUBLIC_GROUP_DETAIL_SOURCE")
      sign_in viewer

      get jjaek_path(group_jjaek)

      expect(response.body).to include(new_jjaek_path(quoted_jjaek_id: group_jjaek.id))
    end

    it "does not show the requote action on approval, private, or inactive group originals" do
      sign_in viewer

      %i[approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Hidden #{group_type}", group_type:)
        group.group_memberships.create!(user: viewer, status: :active)
        group_jjaek = original_author.jjaeks.create!(group:, content: "HIDDEN_GROUP_REQUOTE_ACTION")

        get jjaek_path(group_jjaek)
        expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: group_jjaek.id))
      end

      inactive_group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Hidden inactive", group_type: :public_group)
      inactive_group.group_memberships.create!(user: viewer, status: :active)
      inactive_jjaek = original_author.jjaeks.create!(group: inactive_group, content: "HIDDEN_INACTIVE_REQUOTE_ACTION")
      viewer.jjaeks.create!(quoted_jjaek: inactive_jjaek, content: "EXISTING_INACTIVE_SOURCE_REQUOTE")
      inactive_group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)

      get jjaek_path(inactive_jjaek)
      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: inactive_jjaek.id))
      expect(response.body).not_to include(jjaek_requotes_path(inactive_jjaek))
    end

    it "hides a public group requote after a non-member loses source access" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Source access loss", group_type: :public_group)
      group_jjaek = original_author.jjaeks.create!(group:, content: "GROUP_SOURCE_BEFORE_INACTIVE")
      group_requote = viewer.jjaeks.create!(quoted_jjaek: group_jjaek, content: "GROUP_REQUOTE_AFTER_INACTIVE")
      observer = User.create!(name: "Observer", email: "group-requote-observer@example.com", password: "password123!", password_confirmation: "password123!")
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      sign_in observer

      get jjaek_path(group_requote)

      expect(response).to redirect_to(root_path)
    end

    it "lets a global admin directly inspect private personal and inactive private Group Jjaeks" do
      admin = User.create!(name: "Admin", email: "direct-show-admin@example.com", password: "password123!", global_admin: true)
      private_jjaek = original_author.jjaeks.create!(content: "ADMIN_PRIVATE_DIRECT_SHOW", visibility: :private_jjaek)
      private_group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Admin private group", group_type: :private_group)
      group_jjaek = original_author.jjaeks.create!(group: private_group, content: "ADMIN_GROUP_DIRECT_SHOW")
      private_group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      sign_in admin

      get jjaek_path(private_jjaek)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(private_jjaek.content)

      get jjaek_path(group_jjaek)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(group_jjaek.content)
    end

    it "renders the edit page for a general jjaek without requiring a book" do
      general_jjaek = viewer.jjaeks.create!(content: "GENERAL_EDIT_BODY", visibility: :public_jjaek)
      sign_in viewer

      get edit_jjaek_path(general_jjaek)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("GENERAL_EDIT_BODY")
    end

    it "shows the quoted original when editing a requote" do
      sign_in viewer

      get edit_jjaek_path(requote)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("REQUEST_ORIGINAL_BOOK_FRIENDS_SOURCE")
      expect(response.body).to include(original_author.name)
    end

    it "shows a requote entry on a visible jjaek detail page" do
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include("user_profile_")
      expect(response.body).to include("_128")
      expect(response.body).to include(%(alt="#{original_author.name}"))
      expect(response.body).to include(new_jjaek_path(quoted_jjaek_id: original.id))
    end

    it "does not show a requote entry after the viewer has already requoted the original" do
      requote
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: original.id))
    end

    it "shows a requote entry when only another user has requoted the original" do
      other_requoter = User.create!(name: "Other Requoter", email: "other-requoter@example.com", password: "password123!", password_confirmation: "password123!")
      BookFriendship.create!(requester: other_requoter, addressee: original_author, status: :accepted)
      other_requoter.jjaeks.create!(book:, content: "OTHER_USER_REQUOTE_BODY", quoted_jjaek: original, visibility: :private_jjaek)
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include(new_jjaek_path(quoted_jjaek_id: original.id))
    end

    it "shows the book requote context label on the detail page" do
      sign_in viewer

      get jjaek_path(requote)

      expect(response.body).to include(viewer.name)
      expect(response.body).to include(user_path(viewer))
      expect(response.body).to include(original_author.name)
      expect(response.body).to include(user_path(original_author))
      expect(response.body).to include("ReJjaek request book")
      expect(response.body).to include("Author")
      expect(response.body).to include("user_profile_")
      expect(response.body).to include(%(alt="#{original_author.name}"))
      expect(response.body).to include("님의 책짹을 다시짹")
    end

    it "shows the general requote context label on the detail page" do
      general_original = original_author.jjaeks.create!(content: "REQUEST_ORIGINAL_GENERAL_SOURCE", visibility: :book_friends)
      general_requote = viewer.jjaeks.create!(content: "REQUEST_VIEWER_GENERAL_REQUOTE_BODY", quoted_jjaek: general_original, visibility: :private_jjaek)
      sign_in viewer

      get jjaek_path(general_requote)

      expect(response.body).to include("REQUEST_VIEWER_GENERAL_REQUOTE_BODY")
      expect(response.body).to include("REQUEST_ORIGINAL_GENERAL_SOURCE")
      expect(response.body).to include("님의 짹을 다시짹")
    end

    it "shows written and edited timestamps for an edited jjaek" do
      original.update_column(:content_edited_at, original.created_at + 2.minutes)
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include(I18n.t("jjaeks.meta.created_at", time: I18n.l(original.created_at, format: :short)))
      expect(response.body).to include(I18n.t("jjaeks.meta.edited_at", time: I18n.l(original.content_edited_at, format: :short)))
    end

    it "renders a stable comments panel target" do
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include(%(id="comments_panel_jjaek_#{original.id}"))
      expect(response.body).to include(%(id="comment_action_jjaek_#{original.id}"))
      expect(response.body).to include(%(href="/jjaeks/#{original.id}#comments_panel_jjaek_#{original.id}"))
      expect(response.body).not_to include(%(id="comments_panel_home_jjaek_#{original.id}"))
      expect(response.body).not_to include(%(href="/jjaeks/#{original.id}/comments"))
    end

    it "renders a stable detail requotes panel target" do
      requote
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include(%(id="requotes_panel_jjaek_#{original.id}"))
      expect(response.body).to include(%(href="/jjaeks/#{original.id}/requotes"))
      expect(response.body).to include(%(data-turbo-stream="true"))
      expect(response.body).to include(I18n.t("requotes.actions.view_panel"))
    end

    it "shows the latest quoted original with its edited timestamp" do
      original.update_columns(content: "REQUEST_UPDATED_ORIGINAL_SOURCE", content_edited_at: original.created_at + 2.minutes)
      sign_in viewer

      get jjaek_path(requote)

      expect(response.body).to include("REQUEST_UPDATED_ORIGINAL_SOURCE")
      expect(response.body).to include(I18n.t("jjaeks.meta.edited_at", time: I18n.l(original.content_edited_at, format: :short)))
    end


    it "shows a deleted book jjaek shell without its original body or interaction forms" do
      original.comments.create!(user: viewer, content: "PRESERVED_DELETED_COMMENT")
      original.destroy_or_tombstone!
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).not_to include("REQUEST_ORIGINAL_BOOK_FRIENDS_SOURCE")
      expect(response.body).to include(I18n.t("jjaeks.labels.deleted"), book.title, "PRESERVED_DELETED_COMMENT")
      expect(response.body).to include(I18n.t("jjaeks.meta.deleted_at", time: I18n.l(original.deleted_at, format: :short)))
      expect(response.body).not_to include(%(action="#{jjaek_like_path(original)}"))
      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: original.id))
      expect(response.body).not_to include(%(action="#{jjaek_comments_path(original)}"))
    end

    it "shows a hidden deleted tombstone and preserved comments only to original-context readers" do
      admin = User.create!(name: "Admin", email: "hidden-deleted-request-admin@example.com", password: "password123!", global_admin: true)
      stranger = User.create!(name: "Stranger", email: "hidden-deleted-request-stranger@example.com", password: "password123!")
      original_body = original.content
      original.comments.create!(user: viewer, content: "HIDDEN_DELETED_PRESERVED_COMMENT")
      Jjaeks::Hide.new(original, actor: admin, public_reason: "other").call!

      sign_in viewer
      get jjaek_path(original)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(original_body)

      sign_in original_author
      delete jjaek_path(original)
      expect(original.reload).to be_deleted
      expect(original).to be_hidden

      sign_in viewer
      get jjaek_path(original)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("jjaeks.labels.deleted"), "HIDDEN_DELETED_PRESERVED_COMMENT")
      expect(response.body).not_to include(original_body)

      sign_in stranger
      get jjaek_path(original)
      expect(response).to redirect_to(root_path)
      expect(response.body).not_to include(I18n.t("jjaeks.labels.deleted"))
      expect(response.body).not_to include("HIDDEN_DELETED_PRESERVED_COMMENT")
      expect(response.body).not_to include(original_body)
    end

    it "shows only the tombstone body and comments when a requote itself is deleted" do
      requote.comments.create!(user: original_author, content: "PRESERVED_REQUOTE_COMMENT")
      requote.destroy_or_tombstone!
      sign_in viewer

      get jjaek_path(requote)

      expect(response.body).to include(I18n.t("jjaeks.labels.deleted"), "PRESERVED_REQUOTE_COMMENT")
      expect(response.body).not_to include("REQUEST_VIEWER_REQUOTE_BODY")
      expect(response.body).not_to include("REQUEST_ORIGINAL_BOOK_FRIENDS_SOURCE")
    end

    it "rejects direct comment, like, and requote creation for a deleted jjaek" do
      original.comments.create!(user: viewer, content: "Keeps shell")
      original.destroy_or_tombstone!
      sign_in viewer

      expect {
        post jjaek_comments_path(original), params: { comment: { content: "Blocked" } }
      }.not_to change(Comment, :count)
      expect {
        post jjaek_like_path(original)
      }.not_to change(Like, :count)
      expect {
        post jjaeks_path, params: { jjaek: { content: "Blocked", quoted_jjaek_id: original.id } }
      }.not_to change(Jjaek, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
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

    it "does not count the unsaved comment form object in the detail metadata" do
      original.comments.create!(user: viewer, content: "REQUEST_DETAIL_COMMENT")
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include(I18n.t("jjaeks.meta.comments", count: 1))
      expect(response.body).not_to include(I18n.t("jjaeks.meta.comments", count: 2))
    end

    it "shows the visible requote count on the original jjaek" do
      requote
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1))
      expect(response.body).to include(jjaek_requotes_path(original))
    end

    it "does not show a requote count when the jjaek has no visible requotes" do
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).not_to include(I18n.t("jjaeks.meta.requotes", count: 1))
    end

    it "does not include requotes the viewer cannot see in the count" do
      hidden_requoter = User.create!(name: "Hidden Requoter", email: "hidden-requoter@example.com", password: "password123!", password_confirmation: "password123!")
      BookFriendship.create!(requester: hidden_requoter, addressee: original_author, status: :accepted)
      hidden_requoter.jjaeks.create!(
        content: "HIDDEN_BOOK_FRIENDS_REQUOTE",
        quoted_jjaek: original,
        visibility: :book_friends
      )
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).not_to include(I18n.t("jjaeks.meta.requotes", count: 1))
      expect(response.body).not_to include("HIDDEN_BOOK_FRIENDS_REQUOTE")
    end

    it "includes visible book-friends requotes in the count" do
      visible_requoter = User.create!(name: "Visible Requoter", email: "visible-requoter@example.com", password: "password123!", password_confirmation: "password123!")
      BookFriendship.create!(requester: visible_requoter, addressee: original_author, status: :accepted)
      BookFriendship.create!(requester: viewer, addressee: visible_requoter, status: :accepted)
      visible_requoter.jjaeks.create!(
        content: "VISIBLE_BOOK_FRIENDS_REQUOTE",
        quoted_jjaek: original,
        visibility: :book_friends
      )
      sign_in viewer

      get jjaek_path(original)

      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1))
    end

    it "does not show a requote count on a requote" do
      sign_in viewer

      get jjaek_path(requote)

      expect(response.body).not_to include(I18n.t("jjaeks.meta.requotes", count: 1))
      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: requote.id))
    end

    it "blocks a user's own requote when the original is no longer visible to them" do
      sign_in viewer
      requote
      friendship.destroy!

      get jjaek_path(requote)

      expect(response).to redirect_to(root_path)
    end

    it "blocks a user's own requote when the original becomes private" do
      sign_in viewer
      requote
      original.update!(visibility: :private_jjaek)

      get jjaek_path(requote)

      expect(response).to redirect_to(root_path)
    end

    it "shows a deleted-source requote with a private note to its author" do
      sign_in viewer
      requote
      original.destroy!

      get jjaek_path(requote.reload)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("REQUEST_VIEWER_REQUOTE_BODY")
      expect(response.body).to include(I18n.t("jjaeks.labels.deleted_quoted_source_title.book", name: original_author.name))
      expect(response.body).to include(I18n.t("jjaeks.labels.deleted_quoted_source"))
      expect(response.body).not_to include("REQUEST_ORIGINAL_BOOK_FRIENDS_SOURCE")
    end
  end

  describe "GET /jjaeks/new" do
    it "uses the same stale response for hard-deleted and out-of-scope requote sources" do
      hard_deleted_source = original_author.jjaeks.create!(content: "HARD_DELETED_REQUOTE_FORM_SOURCE")
      hard_deleted_source_id = hard_deleted_source.id
      hard_deleted_source.destroy!
      out_of_scope_source = original
      friendship.destroy!
      sign_in viewer

      get new_jjaek_path, params: { quoted_jjaek_id: hard_deleted_source_id }
      hard_deleted_response = [ response.status, response.location, flash[:alert] ]

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.requote_source_unavailable"))

      get new_jjaek_path, params: { quoted_jjaek_id: out_of_scope_source.id }

      expect([ response.status, response.location, flash[:alert] ]).to eq(hard_deleted_response)
    end

    it "limits requote visibility options for a book-friends original" do
      sign_in viewer
      original

      get new_jjaek_path, params: { quoted_jjaek_id: original.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('option selected="selected" value="book_friends"')
      expect(response.body).to include('option value="private_jjaek"')
      expect(response.body).not_to include('option value="public_jjaek"')
    end

    it "keeps public visibility available for a public original" do
      public_original = original_author.jjaeks.create!(
        book:,
        content: "REQUEST_PUBLIC_REQUOTE_SOURCE",
        visibility: :public_jjaek
      )
      sign_in viewer

      get new_jjaek_path, params: { quoted_jjaek_id: public_original.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('option selected="selected" value="public_jjaek"')
      expect(response.body).to include('option value="book_friends"')
      expect(response.body).to include('option value="private_jjaek"')
    end
  end

  describe "GET /" do
    it "shows a thumbnail card for a book-linked jjaek in the home feed" do
      illustrated_book = Book.create!(
        title: "THUMBNAIL_FEED_BOOK",
        authors_text: "Thumbnail Author",
        thumbnail: "https://example.com/thumbnail.jpg"
      )
      original_author.bookshelf_entries.create!(book: illustrated_book)
      original_author.active_follows.create!(followee: viewer)
      viewer.active_follows.create!(followee: original_author)
      original_author.jjaeks.create!(
        book: illustrated_book,
        content: "REQUEST_BOOK_THUMBNAIL_FEED",
        visibility: :public_jjaek
      )
      sign_in viewer

      get root_path

      expect(response.body).to include("REQUEST_BOOK_THUMBNAIL_FEED")
      expect(response.body).to include("THUMBNAIL_FEED_BOOK")
      expect(response.body).to include("님의 책짹")
      expect(response.body).to include("https://example.com/thumbnail.jpg")
    end

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

    it "does not show a deleted-source requote in another user's home feed" do
      public_original = original_author.jjaeks.create!(content: "REQUEST_PUBLIC_DELETED_SOURCE", visibility: :public_jjaek)
      public_requote = viewer.jjaeks.create!(content: "REQUEST_PUBLIC_REQUOTE_DELETED_SOURCE", quoted_jjaek: public_original, visibility: :public_jjaek)
      observer = User.create!(name: "Observer", email: "observer-deleted-source@example.com", password: "password123!", password_confirmation: "password123!")
      observer.active_follows.create!(followee: viewer)
      public_original.destroy!
      sign_in observer

      get root_path

      expect(response.body).not_to include(public_requote.content)
    end

    it "hides a requote from the home feed when the original becomes private" do
      sign_in viewer
      requote
      original.update!(visibility: :private_jjaek)

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
