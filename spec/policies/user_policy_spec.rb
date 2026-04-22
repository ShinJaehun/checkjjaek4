require "rails_helper"

RSpec.describe UserPolicy do
  let(:user) { User.create!(name: "Reader", email: "user-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "user-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }

  describe "permissions" do
    it "lets a signed-in user view another user's profile" do
      expect(described_class.new(user, other_user).show?).to be(true)
    end

    it "lets a signed-in user follow another user" do
      expect(described_class.new(user, other_user).follow?).to be(true)
    end

    it "does not let a user follow themselves" do
      expect(described_class.new(user, user).follow?).to be(false)
    end

    it "does not let a guest view a profile" do
      expect(described_class.new(nil, other_user).show?).to be(false)
    end

    it "lets a user view and write in their own profile context" do
      policy = described_class.new(user, user)

      expect(policy.show_bookshelf?).to be(true)
      expect(policy.write_jjaek?).to be(true)
    end

    it "lets an accepted book friend view and write in the profile context" do
      BookFriendship.create!(requester: user, addressee: other_user, status: :accepted)
      policy = described_class.new(user, other_user)

      expect(policy.show_bookshelf?).to be(true)
      expect(policy.write_jjaek?).to be(true)
    end

    it "does not let an unrelated user view the bookshelf or write in the profile context" do
      policy = described_class.new(user, other_user)

      expect(policy.show_bookshelf?).to be(false)
      expect(policy.write_jjaek?).to be(false)
    end
  end
end
