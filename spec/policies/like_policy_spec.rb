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

    it "does not let a guest like a jjaek" do
      like = jjaek_record.likes.build(user:)

      expect(described_class.new(nil, like).create?).to be(false)
    end
  end
end
