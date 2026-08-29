require "rails_helper"

RSpec.describe LikePolicy do
  let(:user) { User.create!(name: "Reader", email: "like-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "like-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "좋아요 정책", authors_text: "저자") }
  let(:friendship) { BookFriendship.create!(requester: user, addressee: other_user, status: :accepted) }
  let(:jjaek_record) { other_user.jjaeks.create!(book:, content: "Jjaek") }

  describe "permissions" do
    it "lets a signed-in user like an accessible jjaek" do
      like = jjaek_record.likes.build(user:)

      expect(described_class.new(user, like).create?).to be(true)
    end

    it "lets a user like a book-friends jjaek while the book friendship exists" do
      friendship
      book_friend_jjaek = other_user.jjaeks.create!(book:, content: "Book friend jjaek", visibility: :book_friends)
      like = book_friend_jjaek.likes.build(user:)

      expect(described_class.new(user, like).create?).to be(true)
    end

    it "does not let a user like a book-friends jjaek after the book friendship is removed" do
      friendship.destroy!
      book_friend_jjaek = other_user.jjaeks.create!(book:, content: "Former book friend jjaek", visibility: :book_friends)
      like = book_friend_jjaek.likes.build(user:)

      expect(described_class.new(user, like).create?).to be(false)
    end

    it "lets the user remove their own like" do
      like = jjaek_record.likes.create!(user:)

      expect(described_class.new(user, like).destroy?).to be(true)
    end

    it "does not let another user remove the like" do
      like = jjaek_record.likes.create!(user: other_user)

      expect(described_class.new(user, like).destroy?).to be(false)
    end

    it "does not grant global admins another user's reaction actions" do
      global_admin = User.create!(name: "Global admin", email: "like-global-admin@example.com", password: "password123!", global_admin: true)
      like = jjaek_record.likes.create!(user: other_user)
      private_jjaek = other_user.jjaeks.create!(content: "Private", visibility: :private_jjaek)

      expect(described_class.new(global_admin, private_jjaek.likes.build(user: global_admin)).create?).to be(false)
      expect(described_class.new(global_admin, like).destroy?).to be(false)
    end

    it "does not let a guest like a jjaek" do
      like = jjaek_record.likes.build(user:)

      expect(described_class.new(nil, like).create?).to be(false)
    end

    it "does not allow a new like on a deleted jjaek" do
      jjaek_record.comments.create!(user:, content: "Keeps shell")
      jjaek_record.destroy_or_tombstone!

      expect(described_class.new(user, jjaek_record.likes.build(user:)).create?).to be(false)
    end

    it "lets the owner remove an existing like from a deleted jjaek" do
      like = jjaek_record.likes.create!(user:)
      jjaek_record.comments.create!(user:, content: "Keeps shell")
      jjaek_record.destroy_or_tombstone!

      expect(described_class.new(user, jjaek_record.likes.build(user:)).create?).to be(false)
      expect(described_class.new(user, like).destroy?).to be(true)
    end

    it "does not let another user remove a like from a deleted jjaek" do
      like = jjaek_record.likes.create!(user:)
      jjaek_record.comments.create!(user:, content: "Keeps shell")
      jjaek_record.destroy_or_tombstone!

      expect(described_class.new(other_user, like).destroy?).to be(false)
    end

    it "lets an active member like and unlike group jjaeks and group book jjaeks" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Readers", group_type: :public_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")
      group_book_jjaek = other_user.jjaeks.create!(group:, book:, content: "Group book jjaek")

      [ group_jjaek, group_book_jjaek ].each do |jjaek|
        like = jjaek.likes.build(user:)
        expect(described_class.new(user, like).create?).to be(true)

        like.save!
        expect(described_class.new(user, like).destroy?).to be(true)
      end
    end

    it "does not let a public group non-member create a like" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Public", group_type: :public_group)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")

      expect(described_class.new(user, group_jjaek.likes.build(user:)).create?).to be(false)
    end

    it "uses the same active-member rule for approval and private groups" do
      %i[approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: group_type.to_s, group_type:)
        group.group_memberships.create!(user:, status: :active)
        group_jjaek = other_user.jjaeks.create!(group:, content: group_type.to_s)

        expect(described_class.new(user, group_jjaek.likes.build(user:)).create?).to be(true)
      end
    end

    it "does not let an inactive group or inactive membership create a like" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Readers", group_type: :public_group)
      membership = group.group_memberships.create!(user:, status: :active)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")

      membership.update!(status: :inactive)
      expect(described_class.new(user, group_jjaek.likes.build(user:)).create?).to be(false)

      membership.update!(status: :active)
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      expect(described_class.new(user, group_jjaek.likes.build(user:)).create?).to be(false)
    end

    it "lets the owner remove a visible group like after the group or membership becomes inactive" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Readers", group_type: :public_group)
      membership = group.group_memberships.create!(user:, status: :active)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")
      like = group_jjaek.likes.create!(user:)

      membership.update!(status: :inactive)
      expect(described_class.new(user, like).destroy?).to be(true)

      membership.update!(status: :active)
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      expect(described_class.new(user, like).destroy?).to be(true)
    end

    it "does not let the owner remove a group like after membership ends and the jjaek is no longer visible" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Private", group_type: :private_group)
      membership = group.group_memberships.create!(user:, status: :active)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")
      like = group_jjaek.likes.create!(user:)

      membership.destroy!

      expect(described_class.new(user, like).destroy?).to be(false)
    end

    it "blocks a new like but allows an existing own like on a tombstoned group jjaek to be removed" do
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Readers", group_type: :public_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = other_user.jjaeks.create!(group:, content: "Group jjaek")
      like = group_jjaek.likes.create!(user:)
      group_jjaek.comments.create!(user:, content: "Keeps shell")
      group_jjaek.destroy_or_tombstone!

      expect(described_class.new(user, group_jjaek.likes.build(user:)).create?).to be(false)
      expect(described_class.new(user, like).destroy?).to be(true)
      expect(described_class.new(other_user, like).destroy?).to be(false)
    end
  end
end
