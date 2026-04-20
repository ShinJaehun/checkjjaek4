require "rails_helper"

RSpec.describe LikePolicy do
  let(:user) { User.create!(name: "Reader", email: "like-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "like-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "좋아요 정책", authors_text: "저자") }
  let(:post_record) { other_user.jjaeks.create!(book:, content: "Post") }

  describe "permissions" do
    it "lets a signed-in user like an accessible post" do
      like = post_record.likes.build(user:)

      expect(described_class.new(user, like).create?).to be(true)
    end

    it "lets the user remove their own like" do
      like = post_record.likes.create!(user:)

      expect(described_class.new(user, like).destroy?).to be(true)
    end

    it "does not let another user remove the like" do
      like = post_record.likes.create!(user: other_user)

      expect(described_class.new(user, like).destroy?).to be(false)
    end

    it "does not let a guest like a post" do
      like = post_record.likes.build(user:)

      expect(described_class.new(nil, like).create?).to be(false)
    end
  end
end
