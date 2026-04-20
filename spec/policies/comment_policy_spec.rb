require "rails_helper"

RSpec.describe CommentPolicy do
  let(:user) { User.create!(name: "Reader", email: "comment-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "comment-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "댓글 정책", authors_text: "저자") }
  let(:post_record) { other_user.jjaeks.create!(book:, content: "Post") }

  describe "permissions" do
    it "lets a signed-in user create a comment on an accessible post" do
      comment = post_record.comments.build(user:, content: "Nice")

      expect(described_class.new(user, comment).create?).to be(true)
    end

    it "lets the author update their own comment" do
      comment = post_record.comments.create!(user:, content: "Mine")

      expect(described_class.new(user, comment).update?).to be(true)
    end

    it "does not let another user update the comment" do
      comment = post_record.comments.create!(user: other_user, content: "Theirs")

      expect(described_class.new(user, comment).update?).to be(false)
    end

    it "does not let a guest create a comment" do
      comment = post_record.comments.build(user:, content: "Nice")

      expect(described_class.new(nil, comment).create?).to be(false)
    end
  end
end
