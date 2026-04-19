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
  end
end
