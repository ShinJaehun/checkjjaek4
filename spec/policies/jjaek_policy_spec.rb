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

  it "separates hidden jjaek inspection, author cleanup, and ordinary interaction" do
    admin = User.create!(name: "Admin", email: "jjaek-hide-policy-admin@example.com", password: "password123!", global_admin: true)
    hidden_jjaek = original_author.jjaeks.create!(content: "HIDDEN_POLICY_SOURCE")
    Jjaeks::Hide.new(hidden_jjaek, actor: admin, public_reason: "other").call!
    ModerationAction.create!(target: hidden_jjaek, actor: admin, action_type: :hide, public_reason: "other", moderation_authority: "platform")

    admin_policy = described_class.new(admin, hidden_jjaek)
    expect(admin_policy).not_to be_hide
    expect(admin_policy).to be_restore
    expect(admin_policy).to be_show
    expect(admin_policy).to be_view_hidden_read_actions
    expect(admin_policy).not_to be_update
    expect(admin_policy).not_to be_destroy

    author_policy = described_class.new(original_author, hidden_jjaek)
    expect(author_policy).to be_show
    expect(author_policy).to be_view_hidden_read_actions
    expect(author_policy).not_to be_view_admin_inventory
    expect(author_policy).not_to be_restore
    expect(author_policy).not_to be_visible_for_interaction
    expect(author_policy).not_to be_update
    expect(author_policy).to be_destroy

    viewer_policy = described_class.new(viewer, hidden_jjaek)
    expect(viewer_policy).to be_show
    expect(viewer_policy).to be_view_hidden_read_actions
    expect(viewer_policy).not_to be_visible_for_interaction
    expect(viewer_policy).not_to be_hide
  end

  it "uses author permissions when a global admin views their own hidden jjaek" do
    admin_author = User.create!(name: "Admin author", email: "jjaek-admin-author@example.com", password: "password123!", global_admin: true)
    hidden_jjaek = admin_author.jjaeks.create!(content: "ADMIN AUTHORED", hidden_at: Time.current)
    policy = described_class.new(admin_author, hidden_jjaek)

    expect(policy).to be_show
    expect(policy).to be_view_hidden_content
    expect(policy).not_to be_view_admin_inventory
    expect(policy).not_to be_hide
    expect(policy).not_to be_restore
    expect(policy).not_to be_update
    expect(policy).to be_destroy
  end

  it "does not let a global admin hide or restore a current peer's jjaek" do
    admin = User.create!(name: "Moderating admin", email: "jjaek-peer-moderator@example.com", password: "password123!", global_admin: true)
    peer = User.create!(name: "Peer admin", email: "jjaek-peer-author@example.com", password: "password123!")
    visible = peer.jjaeks.create!(content: "Peer visible")
    hidden = peer.jjaeks.create!(content: "Peer hidden", hidden_at: Time.current)
    ModerationAction.create!(target: hidden, actor: admin, action_type: :hide, public_reason: "other", moderation_authority: "platform")
    peer.update!(global_admin: true)

    expect(described_class.new(admin, visible)).not_to be_hide
    expect(described_class.new(admin, hidden)).not_to be_restore
  end

  it "excludes hidden sources and their requotes from ordinary scopes but keeps admin investigation" do
    admin = User.create!(name: "Admin", email: "jjaek-hide-scope-admin@example.com", password: "password123!", global_admin: true)
    source = original_author.jjaeks.create!(content: "HIDDEN_SCOPE_SOURCE")
    existing_requote = viewer.jjaeks.create!(content: "HIDDEN_SCOPE_REQUOTE", quoted_jjaek: source, visibility: :private_jjaek)
    source.update!(hidden_at: Time.current)

    expect(described_class::Scope.new(viewer, Jjaek.all).resolve).not_to include(source, existing_requote)
    expect(described_class::FeedScope.new(viewer, Jjaek.all).resolve).not_to include(source, existing_requote)
    expect(described_class::ProfileScope.new(viewer, original_author.jjaeks).resolve).not_to include(source)
    expect(described_class::ProfileScope.new(original_author, original_author.jjaeks).resolve).to include(source)
    expect(described_class::FeedScope.new(original_author, Jjaek.all).resolve).to include(source)
    expect(described_class::AdminInventoryScope.new(admin, Jjaek.all).resolve).to include(source, existing_requote)
    expect(described_class::ProfileScope.new(admin, original_author.jjaeks).resolve).to include(source)
  end

  it "keeps hidden group jjaeks for their author and group admin while group read access remains valid" do
    group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Hidden group scope", group_type: :private_group)
    author_membership = group.group_memberships.create!(user: viewer, status: :active)
    other_member = User.create!(name: "Other member", email: "hidden-group-other@example.com", password: "password123!")
    group.group_memberships.create!(user: other_member, status: :active)
    hidden_jjaek = viewer.jjaeks.create!(group:, content: "HIDDEN_GROUP_SCOPE", hidden_at: Time.current)

    expect(described_class::GroupContentScope.new(viewer, group.jjaeks).resolve).to include(hidden_jjaek)
    expect(described_class::GroupContentScope.new(original_author, group.jjaeks).resolve).to include(hidden_jjaek)
    expect(described_class.new(original_author, hidden_jjaek)).to be_show
    expect(described_class.new(original_author, hidden_jjaek)).not_to be_restore
    expect(described_class::GroupContentScope.new(other_member, group.jjaeks).resolve).not_to include(hidden_jjaek)

    author_membership.destroy!
    expect(described_class::GroupContentScope.new(viewer, group.jjaeks).resolve).not_to include(hidden_jjaek)
  end

  it "limits group admin moderation to eligible jjaeks and group-originated hides" do
    group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Moderated group", group_type: :private_group)
    group.group_memberships.create!(user: original_author, status: :active)
    group_jjaek = original_author.jjaeks.create!(group:, content: "Group target")
    policy = described_class.new(viewer, group_jjaek)

    expect(policy).to be_hide_as_group_admin
    expect(described_class.new(viewer, viewer.jjaeks.create!(group:, content: "Own"))).not_to be_hide_as_group_admin
    expect(described_class.new(viewer, original_author.jjaeks.create!(content: "Personal"))).not_to be_hide_as_group_admin

    global_author = User.create!(name: "Global author", email: "group-moderation-global-author@example.com", password: "password123!", global_admin: true)
    global_jjaek = global_author.jjaeks.create!(group:, content: "Global target")
    expect(described_class.new(viewer, global_jjaek)).not_to be_hide_as_group_admin

    ModerationAction.create!(target: group_jjaek, actor: viewer, action_type: :hide, public_reason: "other", moderation_authority: "group")
    group_jjaek.update!(hidden_at: Time.current)
    expect(described_class.new(viewer, group_jjaek)).to be_restore_as_group_admin

    inactive_target = original_author.jjaeks.create!(group:, content: "Inactive target")
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    expect(described_class.new(viewer, inactive_target)).not_to be_hide_as_group_admin
    expect(described_class.new(viewer, group_jjaek)).to be_restore_as_group_admin

    original_author.update!(global_admin: true)
    expect(described_class.new(viewer, group_jjaek)).to be_restore_as_group_admin
    expect(described_class.new(viewer, original_author.jjaeks.create!(group:, content: "New global target"))).not_to be_hide_as_group_admin

    global_admin = User.create!(name: "Global admin", email: "group-moderation-global@example.com", password: "password123!", global_admin: true)
    ModerationAction.create!(target: global_jjaek, actor: global_admin, action_type: :hide, public_reason: "other", moderation_authority: "platform")
    global_jjaek.update!(hidden_at: Time.current)
    expect(described_class.new(viewer, global_jjaek)).not_to be_restore_as_group_admin
  end

  it "rejects platform and group moderation transitions for deleted jjaeks" do
    admin = User.create!(name: "Admin", email: "deleted-jjaek-policy-admin@example.com", password: "password123!", global_admin: true)
    group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Deleted moderation", group_type: :private_group)
    group.group_memberships.create!(user: original_author, status: :active)

    deleted_jjaek = original_author.jjaeks.create!(group:, content: "Deleted target")
    deleted_jjaek.comments.create!(user: viewer, content: "Preserved comment")
    deleted_jjaek.destroy_or_tombstone!

    expect(described_class.new(admin, deleted_jjaek)).not_to be_hide
    expect(described_class.new(viewer, deleted_jjaek)).not_to be_hide_as_group_admin

    hidden_deleted_jjaek = original_author.jjaeks.create!(group:, content: "Hidden deleted target")
    hidden_deleted_jjaek.comments.create!(user: viewer, content: "Preserved comment")
    Jjaeks::Hide.new(hidden_deleted_jjaek, actor: viewer, public_reason: "other").call!
    hidden_deleted_jjaek.destroy_or_tombstone!

    expect(described_class.new(admin, hidden_deleted_jjaek)).not_to be_restore
    expect(described_class.new(viewer, hidden_deleted_jjaek)).not_to be_restore_as_group_admin
  end

  it "allows only original-context readers to view a hidden deleted tombstone" do
    admin = User.create!(name: "Admin", email: "deleted-tombstone-policy-admin@example.com", password: "password123!", global_admin: true)
    hidden_jjaek = original
    hidden_jjaek.comments.create!(user: viewer, content: "Preserved comment")
    Jjaeks::Hide.new(hidden_jjaek, actor: admin, public_reason: "other").call!

    live_policy = described_class.new(viewer, hidden_jjaek)
    expect(live_policy).not_to be_view_deleted_tombstone
    expect(live_policy).not_to be_view_original_content

    hidden_jjaek.destroy_or_tombstone!

    reader_policy = described_class.new(viewer, hidden_jjaek)
    expect(reader_policy).to be_view_deleted_tombstone
    expect(reader_policy).not_to be_view_original_content
    expect(reader_policy).to be_show

    outsider_policy = described_class.new(unrelated_author, hidden_jjaek)
    expect(outsider_policy).not_to be_view_deleted_tombstone
    expect(outsider_policy).not_to be_show
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

    it "uses destination Group read access for a deleted-source group share" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Private readers", group_type: :private_group)
      membership = group.group_memberships.create!(user: viewer, status: :active)
      source = original_author.jjaeks.create!(content: "PERSONAL_GROUP_SOURCE")
      share = viewer.jjaeks.create!(group:, content: "GROUP_DISCUSSION", quoted_jjaek: source)
      source.destroy!
      share.reload

      expect(described_class.new(original_author, share)).to be_visible_for_interaction
      expect(described_class::Scope.new(original_author, Jjaek.all).resolve).to include(share)
      expect(described_class::ProfileScope.new(original_author, viewer.jjaeks).resolve).to include(share)
      expect(described_class::GroupContentScope.new(original_author, group.jjaeks).resolve).to include(share)
      expect(CommentPolicy.new(original_author, share.comments.build(user: original_author, content: "Reply"))).to be_create
      expect(LikePolicy.new(original_author, share.likes.build(user: original_author))).to be_create
      expect(described_class.new(unrelated_author, share)).not_to be_show
      expect(described_class::Scope.new(unrelated_author, Jjaek.all).resolve).not_to include(share)

      membership.destroy!
      expect(described_class.new(viewer, share)).not_to be_show
      expect(described_class::GroupContentScope.new(viewer, group.jjaeks).resolve).not_to include(share)
      expect(CommentPolicy.new(viewer, share.comments.build(user: viewer, content: "Blocked"))).not_to be_create
    end

    it "keeps deleted-source group quotes readable but blocks new interaction when Group activity stops" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Private readers", group_type: :private_group)
      membership = group.group_memberships.create!(user: viewer, status: :active)
      source = original_author.jjaeks.create!(group:, content: "GROUP_SOURCE")
      quote = viewer.jjaeks.create!(group:, content: "GROUP_QUOTE", quoted_jjaek: source)
      source.destroy!
      quote.reload

      membership.update!(moderation_status: :activity_suspended)
      expect(described_class.new(viewer, quote)).to be_show
      expect(CommentPolicy.new(viewer, quote.comments.build(user: viewer, content: "Blocked"))).not_to be_create
      membership.update!(moderation_status: :normal)

      group.update!(operation_suspended_at: Time.current)
      quote.reload
      expect(described_class.new(viewer, quote)).to be_visible_for_interaction
      expect(described_class::GroupActivityScope.new(viewer, Jjaek.all).resolve).to include(quote)
      expect(CommentPolicy.new(viewer, quote.comments.build(user: viewer, content: "Blocked"))).not_to be_create
      expect(LikePolicy.new(viewer, quote.likes.build(user: viewer))).not_to be_create

      group.update!(operation_suspended_at: nil, lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      quote.reload
      expect(described_class.new(viewer, quote)).to be_show
      expect(described_class::GroupContentScope.new(viewer, group.jjaeks).resolve).to include(quote)
      expect(CommentPolicy.new(viewer, quote.comments.build(user: viewer, content: "Blocked"))).not_to be_create
    end

    it "keeps a hidden source linked and rechecks it after restoration" do
      admin = User.create!(name: "Admin", email: "hidden-quote-source-admin@example.com", password: "password123!", global_admin: true)
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Private readers", group_type: :private_group)
      group.group_memberships.create!(user: viewer, status: :active)
      source = original_author.jjaeks.create!(group:, content: "HIDDEN_GROUP_SOURCE")
      quote = viewer.jjaeks.create!(group:, content: "GROUP_QUOTE", quoted_jjaek: source)

      Jjaeks::Hide.new(source, actor: admin, public_reason: "other").call!

      expect(quote.reload.quoted_jjaek_id).to eq(source.id)
      expect(quote).not_to be_quoted_source_deleted
      expect(described_class.new(viewer, quote)).not_to be_show
      expect(described_class.new(viewer, quote)).not_to be_view_quoted_source
      expect(described_class.new(admin, quote)).to be_show
      expect(described_class.new(admin, quote)).not_to be_view_quoted_source
      expect(described_class::Scope.new(viewer, Jjaek.all).resolve).not_to include(quote)
      expect(described_class::GroupContentScope.new(viewer, group.jjaeks).resolve).not_to include(quote)
      expect(described_class::ProfileScope.new(original_author, viewer.jjaeks).resolve).not_to include(quote)

      Jjaeks::Restore.new(source, actor: admin, public_reason: "Restored").call!

      expect(quote.reload.quoted_jjaek_id).to eq(source.id)
      expect(described_class.new(viewer, quote)).to be_show
      expect(described_class.new(viewer, quote)).to be_view_quoted_source
      expect(described_class::Scope.new(viewer, Jjaek.all).resolve).to include(quote)
      expect(described_class::GroupContentScope.new(viewer, group.jjaeks).resolve).to include(quote)
      expect(ModerationAction.where(target: source).count).to eq(2)
    end

    it "does not treat a still-present but inaccessible personal source as deleted" do
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Readers", group_type: :public_group)
      source = original_author.jjaeks.create!(content: "PUBLIC_SOURCE")
      share = viewer.jjaeks.create!(group:, content: "GROUP_SHARE", quoted_jjaek: source)

      source.update!(visibility: :private_jjaek)

      expect(share.reload.quoted_jjaek_id).to eq(source.id)
      expect(share).not_to be_quoted_source_deleted
      expect(described_class.new(viewer, share)).not_to be_show
      expect(described_class::Scope.new(viewer, Jjaek.all).resolve).not_to include(share)

      source.update!(visibility: :public_jjaek)
      share.reload
      expect(described_class.new(viewer, share)).to be_show
      expect(described_class::Scope.new(viewer, Jjaek.all).resolve).to include(share)
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

    it "keeps the personal requote available after a same-group quote of a public group original" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Personal requote boundary", group_type: :public_group)
      group.group_memberships.create!(user: viewer, status: :active)
      source = original_author.jjaeks.create!(group:, content: "PUBLIC_GROUP_SOURCE")
      viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "GROUP_QUOTE")

      expect(described_class.new(viewer, source).requote?).to be(true)
      expect(described_class.new(viewer, source).create_requote?).to be(true)

      viewer.jjaeks.create!(quoted_jjaek: source, content: "PERSONAL_REQUOTE")
      expect(described_class.new(viewer, source).create_requote?).to be(false)
    end
  end

  describe "#view_requotes?" do
    it "allows reading a visible original's list after the viewer has requoted it" do
      requote

      expect(described_class.new(viewer, original).create_requote?).to be(false)
      expect(described_class.new(viewer, original).view_requotes?).to be(true)
    end

    it "allows a member to read a restricted group original's list without personal requote permission" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Members' list", group_type: :private_group)
      group.group_memberships.create!(user: viewer, status: :active)
      source = original_author.jjaeks.create!(group:, content: "GROUP_SOURCE")

      expect(described_class.new(viewer, source).requote?).to be(false)
      expect(described_class.new(viewer, source).view_requotes?).to be(true)

      group.group_memberships.find_by!(user: viewer).destroy!
      expect(described_class.new(viewer, source).view_requotes?).to be(false)
    end

    it "does not allow lists for hidden, deleted, or nested sources" do
      expect(described_class.new(viewer, requote).view_requotes?).to be(false)

      original.update!(hidden_at: Time.current)
      expect(described_class.new(viewer, original).view_requotes?).to be(false)

      original.update!(hidden_at: nil, deleted_at: Time.current)
      expect(described_class.new(viewer, original).view_requotes?).to be(false)
    end
  end

  describe "restricted requote metadata" do
    it "separates the source author's metadata access from group content access" do
      source = original_author.jjaeks.create!(book:, content: "PUBLIC_BOOK_SOURCE")
      approval_group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Approval readers", group_type: :approval_group)
      private_group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Private readers", group_type: :private_group)
      approval_requote = viewer.jjaeks.create!(group: approval_group, quoted_jjaek: source, content: "APPROVAL_OPINION")
      private_requote = viewer.jjaeks.create!(group: private_group, quoted_jjaek: source, content: "PRIVATE_OPINION")
      author_policy = described_class.new(original_author, source)

      expect(described_class.new(original_author, approval_requote).visible_for_interaction?).to be(false)
      expect(described_class.new(original_author, private_requote).visible_for_interaction?).to be(false)
      expect(author_policy.view_restricted_requote_details?(approval_requote)).to be(true)
      expect(author_policy.view_restricted_requote_details?(private_requote)).to be(false)

      restricted = described_class::RestrictedRequoteScope.new(original_author, source.requotes).resolve
      expect(restricted).to contain_exactly(approval_requote, private_requote)
      expect(described_class::RestrictedRequoteScope.new(unrelated_author, source.requotes).resolve).to be_empty

      approval_group.group_memberships.create!(user: original_author, status: :active)
      expect(described_class::RestrictedRequoteScope.new(original_author, source.requotes).resolve).to contain_exactly(private_requote)
    end

    it "excludes hidden and deleted group requotes" do
      source = original_author.jjaeks.create!(content: "SOURCE")
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Approval readers", group_type: :approval_group)
      requote = viewer.jjaeks.create!(group:, quoted_jjaek: source, content: "GROUP_OPINION")
      restricted = -> { described_class::RestrictedRequoteScope.new(original_author, source.requotes).resolve }

      requote.update!(hidden_at: Time.current)
      expect(restricted.call).to be_empty

      requote.update!(hidden_at: nil, deleted_at: Time.current)
      expect(restricted.call).to be_empty

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

    it "does not allow creating a profile-context jjaek targeted at oneself" do
      jjaek = viewer.jjaeks.build(
        target_user: viewer,
        content: "SELF_TARGETED_NEW_JJAEK",
        visibility: :public_jjaek
      )

      expect(described_class.new(viewer, jjaek).create?).to be(false)
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

    it "allows public personal originals in multiple writable groups without widening personal requotes" do
      source = original_author.jjaeks.create!(content: "PUBLIC_PERSONAL_SOURCE")
      groups = %i[public_group approval_group private_group].map do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: group_type.to_s, group_type:)
        group.group_memberships.create!(user: viewer, status: :active)
        group
      end

      groups.each do |group|
        quote = viewer.jjaeks.build(group:, quoted_jjaek: source, content: "GROUP_OPINION")
        expect(described_class.new(viewer, quote).create?).to be(true)
        quote.save!
      end

      expect(described_class.new(viewer, source).create_requote?).to be(true)
      duplicate = viewer.jjaeks.build(group: groups.first, quoted_jjaek: source, content: "DUPLICATE_OPINION")
      expect(described_class.new(viewer, duplicate).create?).to be(false)
    end

    it "rejects restricted, deleted, hidden, and nested personal sources for group sharing" do
      group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Source restrictions", group_type: :public_group)
      public_source = original_author.jjaeks.create!(content: "PUBLIC_SOURCE")
      friend_source = original
      private_source = original_author.jjaeks.create!(content: "PRIVATE_SOURCE", visibility: :private_jjaek)
      nested_source = viewer.jjaeks.create!(quoted_jjaek: public_source, content: "FIRST_REQUOTE")
      hidden_source = original_author.jjaeks.create!(content: "HIDDEN_SOURCE", hidden_at: Time.current)
      deleted_source = original_author.jjaeks.create!(content: "DELETED_SOURCE")
      deleted_source.comments.create!(user: viewer, content: "Preserved comment")
      deleted_source.destroy_or_tombstone!

      [ friend_source, private_source, nested_source, hidden_source, deleted_source ].each do |source|
        quote = viewer.jjaeks.build(group:, quoted_jjaek: source, content: "BLOCKED_GROUP_OPINION")
        expect(described_class.new(viewer, quote).create?).to be(false)
      end
    end

    it "allows same-group quotes in public, approval, and private groups but not cross-group quotes" do
      destination = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Other destination", group_type: :public_group)

      %i[public_group approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: group_type.to_s, group_type:)
        group.group_memberships.create!(user: viewer, status: :active)
        source = original_author.jjaeks.create!(group:, content: "GROUP_SOURCE")
        same_group = viewer.jjaeks.build(group:, quoted_jjaek: source, content: "SAME_GROUP_OPINION")
        other_group = viewer.jjaeks.build(group: destination, quoted_jjaek: source, content: "CROSS_GROUP_OPINION")

        expect(described_class.new(viewer, same_group).create?).to be(true)
        expect(described_class.new(viewer, other_group).create?).to be(false)
        expect(described_class.new(viewer, source).requote?).to eq(group.public_group?)

        same_group.save!
        duplicate = viewer.jjaeks.build(group:, quoted_jjaek: source, content: "DUPLICATE_GROUP_OPINION")
        nested = viewer.jjaeks.build(group:, quoted_jjaek: same_group, content: "NESTED_GROUP_OPINION")
        expect(described_class.new(viewer, duplicate).create?).to be(false)
        expect(described_class.new(viewer, nested).create?).to be(false)

        source.update!(hidden_at: Time.current)
        expect(described_class.new(viewer, viewer.jjaeks.build(group:, quoted_jjaek: source, content: "HIDDEN_SOURCE_OPINION")).create?).to be(false)
      end
    end

    it "does not let a public-group reader quote without current write permission" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Readable public group", group_type: :public_group)
      source = original_author.jjaeks.create!(group:, content: "PUBLIC_GROUP_SOURCE")
      quote = viewer.jjaeks.build(group:, quoted_jjaek: source, content: "GROUP_OPINION")

      expect(described_class.new(viewer, source).visible_for_interaction?).to be(true)
      expect(described_class.new(viewer, quote).create?).to be(false)
    end

    it "requires current membership and activity permission for group quotes" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Membership boundary", group_type: :private_group)
      membership = group.group_memberships.create!(user: viewer, status: :active)
      group_source = original_author.jjaeks.create!(group:, content: "PRIVATE_GROUP_SOURCE")
      personal_source = original_author.jjaeks.create!(content: "PUBLIC_PERSONAL_SOURCE")
      quotes = [ group_source, personal_source ].map do |source|
        viewer.jjaeks.build(group:, quoted_jjaek: source, content: "GROUP_OPINION")
      end

      quotes.each { |quote| expect(described_class.new(viewer, quote).create?).to be(true) }

      membership.update!(moderation_status: :activity_suspended)
      quotes.each { |quote| expect(described_class.new(viewer, quote).create?).to be(false) }

      membership.update!(moderation_status: :normal)
      membership.destroy!
      quotes.each { |quote| expect(described_class.new(viewer, quote).create?).to be(false) }
    end

    it "blocks new group quotes when the destination becomes inactive or operation-suspended" do
      group = Group.create!(lifecycle_status: :active, group_admin: original_author, name: "Lifecycle boundary", group_type: :public_group)
      group.group_memberships.create!(user: viewer, status: :active)
      group_source = original_author.jjaeks.create!(group:, content: "GROUP_SOURCE")
      personal_source = original_author.jjaeks.create!(content: "PERSONAL_SOURCE")
      quotes = [ group_source, personal_source ].map do |source|
        viewer.jjaeks.build(group:, quoted_jjaek: source, content: "GROUP_OPINION")
      end

      group.update!(operation_suspended_at: Time.current)
      quotes.each { |quote| expect(described_class.new(viewer, quote).create?).to be(false) }

      group.update!(operation_suspended_at: nil)
      group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)
      quotes.each { |quote| expect(described_class.new(viewer, quote).create?).to be(false) }
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

    it "excludes group jjaeks from the home feed even with an active membership" do
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

      expect(resolved).not_to include(*group_jjaeks)
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

    it "excludes group jjaeks from a global admin's home feed regardless of membership" do
      admin = User.create!(name: "Admin", email: "jjaek-group-feed-admin@example.com", password: "password123!", global_admin: true)
      joined_group = Group.create!(lifecycle_status: :active, group_admin: unrelated_author, name: "Admin joined group", group_type: :private_group)
      joined_group.group_memberships.create!(user: admin, status: :active)
      joined_group_jjaek = unrelated_author.jjaeks.create!(group: joined_group, content: "ADMIN_JOINED_GROUP_FEED")
      hidden_group = Group.create!(lifecycle_status: :active, group_admin: unrelated_author, name: "Admin hidden group", group_type: :public_group)
      hidden_group_jjaek = unrelated_author.jjaeks.create!(group: hidden_group, content: "ADMIN_HIDDEN_GROUP_FEED")

      resolved = JjaekPolicy::FeedScope.new(admin, Jjaek.all).resolve

      expect(resolved).not_to include(joined_group_jjaek)
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

    it "includes book-friends jjaeks from followed accepted book friends in the home feed" do
      BookFriendship.create!(requester: viewer, addressee: book_friend_author, status: :accepted)
      viewer.active_follows.create!(followee: book_friend_author)
      book_friend_jjaek = book_friend_author.jjaeks.create!(
        content: "BOOK_FRIENDS_FEED_JJAEK",
        visibility: :book_friends
      )

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(book_friend_jjaek)
    end

    it "does not include public or book-friends jjaeks from an unfollowed book friend" do
      BookFriendship.create!(requester: viewer, addressee: book_friend_author, status: :accepted)
      public_jjaek = book_friend_author.jjaeks.create!(content: "UNFOLLOWED_FRIEND_PUBLIC", visibility: :public_jjaek)
      friends_jjaek = book_friend_author.jjaeks.create!(content: "UNFOLLOWED_FRIEND_ONLY", visibility: :book_friends)

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(public_jjaek, friends_jjaek)
      expect(JjaekPolicy::ProfileScope.new(viewer, book_friend_author.jjaeks).resolve).to include(public_jjaek, friends_jjaek)
    end

    it "includes only public jjaeks from a follow-only user" do
      viewer.active_follows.create!(followee: followed_author)
      public_jjaek = followed_author.jjaeks.create!(content: "FOLLOW_ONLY_PUBLIC", visibility: :public_jjaek)
      friends_jjaek = followed_author.jjaeks.create!(content: "FOLLOW_ONLY_FRIENDS", visibility: :book_friends)

      resolved = JjaekPolicy::FeedScope.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(public_jjaek)
      expect(resolved).not_to include(friends_jjaek)
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
