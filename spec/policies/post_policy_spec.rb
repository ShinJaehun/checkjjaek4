require "rails_helper"

RSpec.describe PostPolicy do
  let(:user) { User.create!(name: "Reader", email: "policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "policy-other@example.com", password: "password123!", password_confirmation: "password123!") }

  describe "permissions" do
    it "lets the author update their own post" do
      post_record = user.posts.create!(content: "Mine")

      expect(described_class.new(user, post_record).update?).to be(true)
    end

    it "does not let another user update the post" do
      post_record = other_user.posts.create!(content: "Theirs")

      expect(described_class.new(user, post_record).update?).to be(false)
    end
  end

  describe PostPolicy::Scope do
    it "returns only the user and followee posts" do
      own_post = user.posts.create!(content: "Mine")
      followee = User.create!(name: "Followee", email: "policy-followee@example.com", password: "password123!", password_confirmation: "password123!")
      visible_post = followee.posts.create!(content: "Visible")
      hidden_user = User.create!(name: "Hidden", email: "hidden@example.com", password: "password123!", password_confirmation: "password123!")
      hidden_post = hidden_user.posts.create!(content: "Hidden")
      user.active_follows.create!(followee: followee)

      resolved = described_class.new(user, Post.all).resolve

      expect(resolved).to include(own_post, visible_post)
      expect(resolved).not_to include(hidden_post)
    end
  end
end
