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

    it "does not create a new comment on a deleted jjaek but keeps existing comment permissions" do
      comment = jjaek_record.comments.create!(user:, content: "Existing")
      jjaek_record.destroy_or_tombstone!

      expect(described_class.new(user, jjaek_record.comments.build(user:, content: "New")).create?).to be(false)
      expect(described_class.new(user, comment).update?).to be(true)
      expect(described_class.new(user, comment).destroy?).to be(true)
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
