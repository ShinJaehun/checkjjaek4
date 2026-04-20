require "rails_helper"

RSpec.describe JjaekPolicy do
  let(:user) { User.create!(name: "Reader", email: "policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "policy-other@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "정책 책", authors_text: "저자") }

  describe "permissions" do
    it "lets a signed-in user view a public jjaek" do
      jjaek = other_user.jjaeks.create!(book:, content: "Visible")

      expect(described_class.new(user, jjaek).show?).to be(true)
    end

    it "lets accepted book friends view a book-friends jjaek" do
      BookFriendship.create!(requester: user, addressee: other_user, status: :accepted)
      jjaek = other_user.jjaeks.create!(book:, content: "Visible", visibility: :book_friends)

      expect(described_class.new(user, jjaek).show?).to be(true)
    end

    it "lets the author update their own jjaek" do
      jjaek = user.jjaeks.create!(book:, content: "Mine")

      expect(described_class.new(user, jjaek).update?).to be(true)
    end
  end

  describe JjaekPolicy::FeedScope do
    it "returns the user and followee public jjaeks" do
      own_jjaek = user.jjaeks.create!(book:, content: "Mine")
      followee = User.create!(name: "Followee", email: "policy-followee@example.com", password: "password123!", password_confirmation: "password123!")
      visible_jjaek = followee.jjaeks.create!(book:, content: "Visible")
      hidden_user = User.create!(name: "Hidden", email: "hidden@example.com", password: "password123!", password_confirmation: "password123!")
      hidden_jjaek = hidden_user.jjaeks.create!(book:, content: "Hidden")
      user.active_follows.create!(followee:)

      resolved = JjaekPolicy::FeedScope.new(user, Jjaek.all).resolve

      expect(resolved).to include(own_jjaek, visible_jjaek)
      expect(resolved).not_to include(hidden_jjaek)
    end
  end
end
