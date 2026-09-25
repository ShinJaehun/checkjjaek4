require "rails_helper"

RSpec.describe CommentPolicy do
  let(:user) { User.create!(name: "Reader", email: "comment-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "comment-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "댓글 정책", authors_text: "저자") }
  let(:friendship) { BookFriendship.create!(requester: user, addressee: other_user, status: :accepted) }
  let(:jjaek_record) { other_user.jjaeks.create!(book:, content: "Jjaek") }

  it "limits admin inventory permission and scope to global admins" do
    admin = User.create!(name: "Admin", email: "comment-inventory-admin@example.com", password: "password123!", global_admin: true)
    comment = jjaek_record.comments.create!(user:, content: "Inventory comment")

    expect(described_class.new(admin, comment).view_admin_inventory?).to be(true)
    expect(described_class.new(user, comment).view_admin_inventory?).to be(false)
    expect(described_class::AdminInventoryScope.new(admin, Comment.all).resolve).to include(comment)
    expect(described_class::AdminInventoryScope.new(user, Comment.all).resolve).to be_empty
  end

  describe "permissions" do
    it "lets a signed-in user create a comment on an accessible jjaek" do
      comment = jjaek_record.comments.build(user:, content: "Nice")

      expect(described_class.new(user, comment).create?).to be(true)
    end

    it "lets a user comment on a book-friends jjaek while the book friendship exists" do
      friendship
      book_friend_jjaek = other_user.jjaeks.create!(book:, content: "Book friend jjaek", visibility: :book_friends)
      comment = book_friend_jjaek.comments.build(user:, content: "Book friend comment")

      expect(described_class.new(user, comment).create?).to be(true)
    end

    it "does not let a user comment on a book-friends jjaek after the book friendship is removed" do
      friendship.destroy!
      book_friend_jjaek = other_user.jjaeks.create!(book:, content: "Former book friend jjaek", visibility: :book_friends)
      comment = book_friend_jjaek.comments.build(user:, content: "Former book friend comment")

      expect(described_class.new(user, comment).create?).to be(false)
    end

    it "lets the author update their own comment" do
      comment = jjaek_record.comments.create!(user:, content: "Mine")

      expect(described_class.new(user, comment).update?).to be(true)
    end

    it "does not let another user update the comment" do
      comment = jjaek_record.comments.create!(user: other_user, content: "Theirs")

      expect(described_class.new(user, comment).update?).to be(false)
    end

    it "does not grant global admins author mutation permissions" do
      admin = User.create!(name: "Admin", email: "comment-mutation-admin@example.com", password: "password123!", global_admin: true)
      comment = jjaek_record.comments.create!(user:, content: "Author only")
      policy = described_class.new(admin, comment)

      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
    end

    it "does not turn operational access into permission to comment" do
      admin = User.create!(name: "Admin", email: "comment-create-admin@example.com", password: "password123!", global_admin: true)
      private_jjaek = other_user.jjaeks.create!(content: "Private", visibility: :private_jjaek)

      expect(described_class.new(admin, private_jjaek.comments.build(user: admin, content: "Blocked")).create?).to be(false)
    end

    it "does not let a guest create a comment" do
      comment = jjaek_record.comments.build(user:, content: "Nice")

      expect(described_class.new(nil, comment).create?).to be(false)
    end

    it "blocks comment creation and updates on a deleted jjaek while preserving author deletion" do
      comment = jjaek_record.comments.create!(user:, content: "Existing")
      jjaek_record.destroy_or_tombstone!

      expect(described_class.new(user, jjaek_record.comments.build(user:, content: "New")).create?).to be(false)
      expect(described_class.new(user, comment).update?).to be(false)
      expect(described_class.new(user, comment).destroy?).to be(true)
    end

    it "does not let the author update an existing comment on a hidden jjaek" do
      comment = jjaek_record.comments.create!(user:, content: "Existing")
      jjaek_record.update!(hidden_at: Time.current)

      expect(described_class.new(user, comment).update?).to be(false)
      expect(described_class.new(user, comment).destroy?).to be(true)
    end

    it "applies global moderation with author-first" do
      admin = User.create!(name: "Global moderator", email: "comment-policy-global-moderator@example.com", password: "password123!", global_admin: true)
      comment = jjaek_record.comments.create!(user:, content: "Target")
      own_comment = jjaek_record.comments.create!(user: admin, content: "Own")
      own_comment.update!(hidden_at: Time.current)

      expect(described_class.new(admin, comment)).to be_hide
      expect(described_class.new(admin, comment)).not_to be_restore
      expect(described_class.new(admin, own_comment)).not_to be_hide
      expect(described_class.new(admin, own_comment)).not_to be_restore
      expect(described_class.new(admin, own_comment)).to be_destroy
    end

    it "limits group moderation to eligible parent groups and preserves promotion restore" do
      group_admin = User.create!(name: "Group admin", email: "comment-policy-group-admin@example.com", password: "password123!")
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Comment group", group_type: :public_group)
      target = other_user.jjaeks.create!(group:, content: "Group target")
      comment = target.comments.create!(user:, content: "Group comment")

      expect(described_class.new(group_admin, comment)).to be_hide_as_group_admin
      expect(described_class.new(group_admin, comment)).not_to be_restore_as_group_admin

      Comments::Hide.new(comment, actor: group_admin, public_reason: "other").call!
      user.update!(global_admin: true)
      expect(described_class.new(group_admin, comment)).to be_restore_as_group_admin

      inactive_comment = target.comments.create!(user: other_user, content: "Inactive target")
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      expect(described_class.new(group_admin, inactive_comment)).not_to be_hide_as_group_admin
      expect(described_class.new(group_admin, comment)).to be_restore_as_group_admin

      comment.update!(hidden_at: nil)
      pending_group = Group.create!(group_admin:, name: "Pending comment group", group_type: :public_group, application_purpose: "Pending")
      pending_comment = other_user.jjaeks.create!(group: pending_group, content: "Pending").comments.create!(user:, content: "Comment")
      expect(described_class.new(group_admin, pending_comment)).not_to be_hide_as_group_admin

      suspended_group = Group.create!(lifecycle_status: :active, operation_suspended_at: Time.current, group_admin:, name: "Suspended comment group", group_type: :public_group)
      suspended_comment = other_user.jjaeks.create!(group: suspended_group, content: "Suspended").comments.create!(user:, content: "Comment")
      expect(described_class.new(group_admin, suspended_comment)).not_to be_hide_as_group_admin
    end

    it "rejects other groups, self comments, and platform restores for group admins" do
      group_admin = User.create!(name: "Group admin", email: "comment-policy-boundary-admin@example.com", password: "password123!")
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Boundary group", group_type: :public_group)
      other_group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Other group", group_type: :public_group)
      own_comment = other_user.jjaeks.create!(group:, content: "Own").comments.create!(user: group_admin, content: "Own comment")
      other_comment = other_user.jjaeks.create!(group: other_group, content: "Other").comments.create!(user:, content: "Other comment")
      other_comment.update!(hidden_at: Time.current)
      ModerationAction.create!(target: other_comment, actor: User.create!(name: "Platform", email: "comment-policy-platform@example.com", password: "password123!", global_admin: true), action_type: :hide, public_reason: "other", moderation_authority: "platform")

      expect(described_class.new(group_admin, own_comment)).not_to be_hide_as_group_admin
      expect(described_class.new(group_admin, other_comment)).not_to be_restore_as_group_admin
    end

    it "allows active members to create and update their own group comments" do
      %i[public_group approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: group_type.to_s, group_type:)
        group.group_memberships.create!(user:, status: :active)
        group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")
        comment = group_jjaek.comments.create!(user:, content: "Mine")

        expect(described_class.new(user, comment).create?).to be(true)
        expect(described_class.new(user, comment).update?).to be(true)
      end
    end

    it "blocks group comment creation and update during operation suspension but allows deletion" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Suspended", group_type: :public_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")
      comment = group_jjaek.comments.create!(user:, content: "Existing")
      group.update!(operation_suspended_at: Time.current)

      expect(described_class.new(user, group_jjaek.comments.build(user:, content: "New")).create?).to be(false)
      expect(described_class.new(user, comment).update?).to be(false)
      expect(described_class.new(user, comment).destroy?).to be(true)
    end

    it "allows public group reading but not commenting for a nonmember" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Public", group_type: :public_group)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")
      comment = group_jjaek.comments.build(user:, content: "Blocked")

      expect(JjaekPolicy.new(user, group_jjaek).show?).to be(true)
      expect(described_class.new(user, comment).create?).to be(false)
    end

    it "blocks group comment creation and update after membership ends" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Approval", group_type: :approval_group)
      membership = group.group_memberships.create!(user:, status: :active)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")
      comment = group_jjaek.comments.create!(user:, content: "Existing")
      membership.destroy!

      expect(described_class.new(user, group_jjaek.comments.build(user:, content: "Blocked")).create?).to be(false)
      expect(described_class.new(user, comment).update?).to be(false)
      expect(described_class.new(user, comment).destroy?).to be(true)
      expect(described_class.new(other_user, comment).destroy?).to be(false)
    end
  end
end
