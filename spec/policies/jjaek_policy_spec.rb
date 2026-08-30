require "rails_helper"

RSpec.describe JjaekPolicy do
  let(:viewer) { User.create!(name: "Reader", email: "jjaek-policy-reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:original_author) { User.create!(name: "Original", email: "jjaek-policy-original@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:followed_author) { User.create!(name: "Followed", email: "jjaek-policy-followed@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:unfollowed_author) { User.create!(name: "Unfollowed", email: "jjaek-policy-unfollowed@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book_friend_author) { User.create!(name: "Book Friend", email: "jjaek-policy-book-friend@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:unrelated_author) { User.create!(name: "Unrelated", email: "jjaek-policy-unrelated@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "ReJjaek policy book", authors_text: "Author") }
  let(:friendship) { BookFriendship.create!(requester: viewer, addressee: original_author, status: :accepted) }
  let(:original) { original_author.jjaeks.create!(book:, content: "ORIGINAL_BOOK_FRIENDS_SOURCE", visibility: :book_friends) }
  let(:requote) { viewer.jjaeks.create!(book:, content: "VIEWER_REQUOTE_BODY", quoted_jjaek: original, visibility: :private_jjaek) }

  before do
    friendship
  end

  it "limits admin inventory permission and scope to global admins" do
    admin = User.create!(name: "Admin", email: "jjaek-inventory-admin@example.com", password: "password123!", global_admin: true)

    expect(described_class.new(admin, original).view_admin_inventory?).to be(true)
    expect(described_class.new(viewer, original).view_admin_inventory?).to be(false)
    expect(described_class::AdminInventoryScope.new(admin, Jjaek.all).resolve).to include(original)
    expect(described_class::AdminInventoryScope.new(viewer, Jjaek.all).resolve).to be_empty
  end

  it "keeps suspended group content readable but blocks creation and editing while allowing deletion" do
    group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Suspended", group_type: :public_group)
    group.group_memberships.create!(user: viewer, status: :active)
    existing = viewer.jjaeks.create!(group:, content: "Existing")
    group.update!(operation_suspended_at: Time.current)

    expect(described_class.new(viewer, existing)).to be_show
    expect(described_class.new(viewer, group.jjaeks.build(user: viewer, content: "New"))).not_to be_create
    expect(described_class.new(viewer, existing)).not_to be_update
    expect(described_class.new(viewer, existing)).to be_destroy
  end

  describe "#show?" do
    it "allows global admin inspection without granting author mutations" do
      admin = User.create!(name: "Admin", email: "jjaek-show-admin@example.com", password: "password123!", global_admin: true)
      private_jjaek = original_author.jjaeks.create!(content: "ADMIN_PRIVATE_POLICY", visibility: :private_jjaek)
      policy = described_class.new(admin, private_jjaek)

      expect(policy.show?).to be(true)
      expect(policy.requote?).to be(false)
      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
      expect(CommentPolicy.new(admin, private_jjaek.comments.build(user: admin, content: "Blocked")).create?).to be(false)
      expect(LikePolicy.new(admin, private_jjaek.likes.build(user: admin)).create?).to be(false)
    end

    it "hides a user's own requote when the original is no longer visible to them" do
      friendship.destroy!

      expect(described_class.new(viewer, requote).show?).to be(false)
    end

    it "hides a user's own requote when the original becomes private" do
      existing_requote = requote
      original.update!(visibility: :private_jjaek)

      expect(described_class.new(viewer, existing_requote).show?).to be(false)
    end

    it "shows a deleted-source requote only to its author" do
      requote
      original.destroy!
      requote.reload

      expect(described_class.new(viewer, requote).show?).to be(true)
      expect(described_class.new(original_author, requote).show?).to be(false)
    end

    it "shows a requote when the original is still visible to the viewer" do
      expect(described_class.new(viewer, requote).show?).to be(true)
    end
  end

  describe JjaekPolicy::ProfileScope do
    it "includes every jjaek from the investigated user's profile for a global admin" do
      admin = User.create!(name: "Admin", email: "jjaek-profile-admin@example.com", password: "password123!", global_admin: true)
      private_jjaek = original_author.jjaeks.create!(content: "ADMIN_PROFILE_PRIVATE", visibility: :private_jjaek)

      resolved = described_class.new(admin, original_author.jjaeks).resolve

      expect(resolved).to include(original, private_jjaek)
    end

    it "keeps private profile jjaeks hidden from an unrelated user" do
      friendship.destroy!
      private_jjaek = original_author.jjaeks.create!(content: "STRANGER_PROFILE_PRIVATE", visibility: :private_jjaek)

      resolved = described_class.new(viewer, original_author.jjaeks).resolve

      expect(resolved).not_to include(private_jjaek)
    end

    it "uses group access rather than profile relationships for group jjaeks" do
      public_group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Profile public", group_type: :public_group)
      approval_group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Profile approval", group_type: :approval_group)
      private_group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Profile private", group_type: :private_group)
      public_jjaek = original_author.jjaeks.create!(group: public_group, content: "PROFILE_PUBLIC_GROUP")
      approval_jjaek = original_author.jjaeks.create!(group: approval_group, content: "PROFILE_APPROVAL_GROUP")
      private_jjaek = original_author.jjaeks.create!(group: private_group, content: "PROFILE_PRIVATE_GROUP")

      book_friend_scope = described_class.new(viewer, original_author.jjaeks).resolve
      expect(book_friend_scope).to include(public_jjaek)
      expect(book_friend_scope).not_to include(approval_jjaek)
      expect(book_friend_scope).not_to include(private_jjaek)

      friendship.destroy!
      viewer.active_follows.create!(followee: original_author)
      following_scope = described_class.new(viewer, original_author.jjaeks).resolve
      expect(following_scope).to include(public_jjaek)
      expect(following_scope).not_to include(approval_jjaek)
      expect(following_scope).not_to include(private_jjaek)

      approval_group.group_memberships.create!(user: viewer, status: :active)
      private_group.group_memberships.create!(user: viewer, status: :active)
      member_scope = described_class.new(viewer, original_author.jjaeks).resolve
      expect(member_scope).to include(public_jjaek, approval_jjaek, private_jjaek)
    end

    it "includes every group jjaek for a global admin without membership" do
      admin = User.create!(name: "Admin", email: "jjaek-profile-group-admin@example.com", password: "password123!", global_admin: true)
      group_jjaeks = %i[public_group approval_group private_group].map do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Admin profile #{group_type}", group_type:)
        original_author.jjaeks.create!(group:, content: "ADMIN_PROFILE_#{group_type}")
      end

      resolved = described_class.new(admin, original_author.jjaeks).resolve

      expect(resolved).to include(*group_jjaeks)
    end
  end

  describe "#requote?" do
    it "allows requoting a visible non-private original" do
      expect(described_class.new(viewer, original).requote?).to be(true)
    end

    it "does not allow requoting a private original" do
      private_original = original_author.jjaeks.create!(
        book:,
        content: "PRIVATE_REQUOTE_SOURCE",
        visibility: :private_jjaek
      )

      expect(described_class.new(original_author, private_original).requote?).to be(false)
    end

    it "does not allow requoting another requote" do
      expect(described_class.new(viewer, requote).requote?).to be(false)
    end

    it "does not allow nested requoting even when a requote has public group context" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Nested public source", group_type: :public_group)
      group_context_requote = original_author.jjaeks.build(group:, quoted_jjaek: original, content: "INVALID_GROUP_REQUOTE")

      expect(described_class.new(viewer, group_context_requote).requote?).to be(false)
    end

    it "allows a non-member to requote an active public group original" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Public source", group_type: :public_group)
      group_jjaek = original_author.jjaeks.create!(group:, content: "PUBLIC_GROUP_SOURCE")

      expect(described_class.new(viewer, group_jjaek).requote?).to be(true)
    end

    it "does not allow active members to requote approval or private group originals" do
      %i[approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: group_type.to_s, group_type:)
        group.group_memberships.create!(user: viewer, status: :active)
        group_jjaek = original_author.jjaeks.create!(group:, content: "RESTRICTED_GROUP_SOURCE")

        expect(described_class.new(viewer, group_jjaek).requote?).to be(false)
      end
    end

    it "does not allow an active member to newly requote an inactive public group original" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Inactive source", group_type: :public_group)
      group.group_memberships.create!(user: viewer, status: :active)
      group_jjaek = original_author.jjaeks.create!(group:, content: "INACTIVE_PUBLIC_SOURCE")
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)

      expect(described_class.new(viewer, group_jjaek).requote?).to be(false)
    end

    it "does not allow requoting a pending public group original" do
      group = Group.create!(group_admin: original_author, name: "Pending source", group_type: :public_group, application_purpose: "Review")
      group_jjaek = original_author.jjaeks.create!(group:, content: "PENDING_PUBLIC_SOURCE")

      expect(described_class.new(original_author, group_jjaek).requote?).to be(false)
    end

    it "does not let global admin operational access enable restricted group requotes" do
      admin = User.create!(name: "Admin", email: "requote-policy-admin@example.com", password: "password123!", global_admin: true)
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Admin restricted source", group_type: :private_group)
      group_jjaek = original_author.jjaeks.create!(group:, content: "ADMIN_RESTRICTED_SOURCE")

      expect(described_class.new(admin, group_jjaek).show?).to be(true)
      expect(described_class.new(admin, group_jjaek).requote?).to be(false)
    end
  end

  describe "#create_requote?" do
    it "allows the button when the viewer has not requoted the original" do
      expect(described_class.new(viewer, original).create_requote?).to be(true)
    end

    it "hides the button when the viewer has already requoted the original" do
      requote

      expect(described_class.new(viewer, original).create_requote?).to be(false)
    end

    it "does not hide the button because another user requoted the original" do
      unrelated_author.jjaeks.create!(book:, content: "OTHER_REQUOTE_BODY", quoted_jjaek: original, visibility: :private_jjaek)

      expect(described_class.new(viewer, original).create_requote?).to be(true)
    end
  end

  describe "#create?" do
    it "allows creating a general jjaek without a book" do
      jjaek = viewer.jjaeks.build(content: "GENERAL_POLICY_JJAEK")

      expect(described_class.new(viewer, jjaek).create?).to be(true)
    end

    it "allows creating a book-linked jjaek when the user has the book in their shelf" do
      viewer.bookshelf_entries.create!(book:)
      jjaek = viewer.jjaeks.build(book:, content: "BOOK_POLICY_JJAEK")

      expect(described_class.new(viewer, jjaek).create?).to be(true)
    end

    it "does not allow creating a book-linked jjaek without a shelf entry" do
      jjaek = viewer.jjaeks.build(book:, content: "NO_SHELF_BOOK_POLICY_JJAEK")

      expect(described_class.new(viewer, jjaek).create?).to be(false)
    end

    it "allows creating a profile-context jjaek for an accepted book friend" do
      jjaek = viewer.jjaeks.build(
        target_user: original_author,
        content: "PROFILE_CONTEXT_POLICY_JJAEK",
        visibility: :book_friends
      )

      expect(described_class.new(viewer, jjaek).create?).to be(true)
    end

    it "does not allow creating a profile-context jjaek for an unrelated user" do
      friendship.destroy!
      jjaek = viewer.jjaeks.build(
        target_user: original_author,
        content: "UNRELATED_PROFILE_CONTEXT_POLICY_JJAEK",
        visibility: :book_friends
      )

      expect(described_class.new(viewer, jjaek).create?).to be(false)
    end

    it "does not allow creating a private profile-context jjaek for another user" do
      jjaek = viewer.jjaeks.build(
        target_user: original_author,
        content: "PRIVATE_PROFILE_CONTEXT_POLICY_JJAEK",
        visibility: :private_jjaek
      )

      expect(described_class.new(viewer, jjaek).create?).to be(false)
    end
  end

  describe described_class::Scope do
    it "shows only public jjaeks from another profile to an unrelated user" do
      friendship.destroy!
      public_jjaek = original_author.jjaeks.create!(content: "PUBLIC_PROFILE_SCOPE", visibility: :public_jjaek)
      private_jjaek = original_author.jjaeks.create!(content: "PRIVATE_PROFILE_SCOPE", visibility: :private_jjaek)

      resolved = described_class.new(viewer, original_author.jjaeks).resolve

      expect(resolved).to include(public_jjaek)
      expect(resolved).not_to include(original)
      expect(resolved).not_to include(private_jjaek)
    end

    it "shows only public jjaeks from another profile to a follow-only user" do
      friendship.destroy!
      viewer.active_follows.create!(followee: original_author)
      public_jjaek = original_author.jjaeks.create!(content: "FOLLOW_PUBLIC_PROFILE_SCOPE", visibility: :public_jjaek)
      private_jjaek = original_author.jjaeks.create!(content: "FOLLOW_PRIVATE_PROFILE_SCOPE", visibility: :private_jjaek)

      resolved = described_class.new(viewer, original_author.jjaeks).resolve

      expect(resolved).to include(public_jjaek)
      expect(resolved).not_to include(original)
      expect(resolved).not_to include(private_jjaek)
    end

    it "shows book-friends jjaeks from another profile to an accepted book friend" do
      public_jjaek = original_author.jjaeks.create!(content: "FRIEND_PUBLIC_PROFILE_SCOPE", visibility: :public_jjaek)

      resolved = described_class.new(viewer, original_author.jjaeks).resolve

      expect(resolved).to include(public_jjaek)
      expect(resolved).to include(original)
    end

    it "shows all jjaeks from your own profile" do
      private_jjaek = viewer.jjaeks.create!(content: "SELF_PRIVATE_PROFILE_SCOPE", visibility: :private_jjaek)

      resolved = described_class.new(viewer, viewer.jjaeks).resolve

      expect(resolved).to include(private_jjaek)
    end

    it "excludes a requote when the original is no longer visible to the viewer" do
      friendship.destroy!

      resolved = described_class.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(requote)
    end

    it "excludes a requote when the original becomes private" do
      existing_requote = requote
      original.update!(visibility: :private_jjaek)

      resolved = described_class.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(existing_requote)
    end

    it "includes a deleted-source requote only in the author's own scope" do
      requote
      original.destroy!
      requote.reload

      expect(described_class.new(viewer, Jjaek.all).resolve).to include(requote)
      expect(described_class.new(original_author, Jjaek.all).resolve).not_to include(requote)
    end

    it "includes a requote when the original is still visible to the viewer" do
      resolved = described_class.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(requote)
    end
  end

  describe described_class::FeedScope do
    it "does not include another user's private jjaek for a global admin" do
      admin = User.create!(name: "Admin", email: "jjaek-feed-admin@example.com", password: "password123!", global_admin: true)
      private_jjaek = original_author.jjaeks.create!(content: "ADMIN_FEED_PRIVATE", visibility: :private_jjaek)

      resolved = JjaekPolicy::FeedScope.new(admin, Jjaek.all).resolve

      expect(resolved).not_to include(private_jjaek)
    end

    it "includes the viewer's own jjaeks in the home feed" do
      own_jjaek = viewer.jjaeks.create!(content: "VIEWER_OWN_FEED_JJAEK", visibility: :private_jjaek)

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(own_jjaek)
    end

    it "includes group jjaeks from every active membership, including inactive groups" do
      group_jjaeks = %i[public_group approval_group private_group].flat_map do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: unrelated_author, name: "Feed #{group_type}", group_type:)
        group.group_memberships.create!(user: viewer, status: :active)

        [
          viewer.jjaeks.create!(group:, content: "Own #{group_type}"),
          unrelated_author.jjaeks.create!(group:, book:, content: "Member #{group_type}")
        ]
      end
      inactive_group = group_jjaeks.first.group
      inactive_group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(*group_jjaeks)
    end

    it "excludes group jjaeks without an active membership" do
      group_jjaeks = %i[public_group approval_group private_group].map do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: unrelated_author, name: "Hidden #{group_type}", group_type:)
        unrelated_author.jjaeks.create!(group:, content: "Hidden #{group_type}")
      end

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      group_jjaeks.each do |group_jjaek|
        expect(resolved).not_to include(group_jjaek)
      end
    end

    it "uses active membership rather than operational authority for a global admin" do
      admin = User.create!(name: "Admin", email: "jjaek-group-feed-admin@example.com", password: "password123!", global_admin: true)
      joined_group = Group.create!(lifecycle_status: :active, group_admin: unrelated_author, name: "Admin joined group", group_type: :private_group)
      joined_group.group_memberships.create!(user: admin, status: :active)
      joined_group_jjaek = unrelated_author.jjaeks.create!(group: joined_group, content: "ADMIN_JOINED_GROUP_FEED")
      hidden_group = Group.create!(lifecycle_status: :active, group_admin: unrelated_author, name: "Admin hidden group", group_type: :public_group)
      hidden_group_jjaek = unrelated_author.jjaeks.create!(group: hidden_group, content: "ADMIN_HIDDEN_GROUP_FEED")

      resolved = JjaekPolicy::FeedScope.new(admin, Jjaek.all).resolve

      expect(resolved).to include(joined_group_jjaek)
      expect(resolved).not_to include(hidden_group_jjaek)
    end

    it "includes public jjaeks from followed users in the home feed" do
      viewer.active_follows.create!(followee: followed_author)
      followed_public_jjaek = followed_author.jjaeks.create!(
        content: "FOLLOWED_PUBLIC_FEED_JJAEK",
        visibility: :public_jjaek
      )

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(followed_public_jjaek)
    end

    it "does not include public jjaeks from unfollowed users in the home feed" do
      unfollowed_public_jjaek = unfollowed_author.jjaeks.create!(
        content: "UNFOLLOWED_PUBLIC_FEED_JJAEK",
        visibility: :public_jjaek
      )

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(unfollowed_public_jjaek)
    end

    it "includes book-friends jjaeks from accepted book friends in the home feed" do
      BookFriendship.create!(requester: viewer, addressee: book_friend_author, status: :accepted)
      book_friend_jjaek = book_friend_author.jjaeks.create!(
        content: "BOOK_FRIENDS_FEED_JJAEK",
        visibility: :book_friends
      )

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(book_friend_jjaek)
    end

    it "does not include book-friends jjaeks from unrelated users in the home feed" do
      unrelated_book_friend_jjaek = unrelated_author.jjaeks.create!(
        content: "UNRELATED_BOOK_FRIENDS_FEED_JJAEK",
        visibility: :book_friends
      )

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(unrelated_book_friend_jjaek)
    end

    it "includes non-private profile-context jjaeks targeted at the viewer" do
      targeted_profile_jjaek = original_author.jjaeks.create!(
        target_user: viewer,
        content: "TARGETED_AT_VIEWER_POLICY_FEED",
        visibility: :book_friends
      )

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(targeted_profile_jjaek)
    end

    it "excludes a requote when the quoted original is no longer visible to the viewer" do
      friendship.destroy!

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(requote)
    end

    it "excludes a requote when the quoted original becomes private" do
      existing_requote = requote
      original.update!(visibility: :private_jjaek)

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(existing_requote)
    end

    it "includes a deleted-source requote only in the author's own feed" do
      requote
      original.destroy!
      requote.reload

      expect(JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve).to include(requote)
      expect(JjaekPolicy::FeedScope.new(original_author, Jjaek.all).resolve).not_to include(requote)
    end

    it "includes a requote when the quoted original is still visible to the viewer" do
      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(requote)
    end
  end
end
