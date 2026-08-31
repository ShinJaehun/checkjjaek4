require "rails_helper"

RSpec.describe UserPolicy do
  let(:user) { User.create!(name: "Reader", email: "user-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "user-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }

  describe "permissions" do
    it "limits admin inventory access and scope to global admins" do
      admin = User.create!(name: "Admin", email: "user-policy-admin@example.com", password: "password123!", global_admin: true)

      expect(described_class.new(admin, other_user).view_admin_inventory?).to be(true)
      expect(described_class.new(user, other_user).view_admin_inventory?).to be(false)
      expect(described_class::AdminInventoryScope.new(admin, User.all).resolve).to include(other_user)
      expect(described_class::AdminInventoryScope.new(user, User.all).resolve).to be_empty
    end

    it "allows a global admin to suspend another active user but not themselves" do
      admin = User.create!(name: "Admin", email: "user-policy-suspend-admin@example.com", password: "password123!", global_admin: true)
      Group.create!(lifecycle_status: :active, group_admin: user, name: "Policy group", group_type: :public_group)

      expect(described_class.new(admin, other_user).suspend?).to be(true)
      expect(described_class.new(admin, admin).suspend?).to be(false)
      expect(described_class.new(user, other_user).suspend?).to be(false)
    end

    it "allows only a global admin to restore a suspended non-withdrawn user" do
      admin = User.create!(name: "Admin", email: "user-policy-restore-admin@example.com", password: "password123!", global_admin: true)
      other_user.update!(suspended_at: Time.current)

      expect(described_class.new(admin, other_user).suspend?).to be(false)
      expect(described_class.new(admin, other_user).restore?).to be(true)
      expect(described_class.new(user, other_user).restore?).to be(false)

      other_user.update_columns(withdrawn_at: Time.current)
      expect(described_class.new(admin, other_user).suspend?).to be(false)
      expect(described_class.new(admin, other_user).restore?).to be(false)
    end

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

      expect(policy.profile_access_level).to eq(:self)
      expect(policy.show_profile_bookshelf?).to be(true)
      expect(policy.show_profile_bookshelf_status?).to be(true)
      expect(policy.show_profile_jjaeks?).to be(true)
      expect(policy.write_profile_jjaek?).to be(true)
    end

    it "lets an accepted book friend view and write in the profile context" do
      BookFriendship.create!(requester: user, addressee: other_user, status: :accepted)
      policy = described_class.new(user, other_user)

      expect(policy.profile_access_level).to eq(:book_friend)
      expect(policy.show_profile_bookshelf?).to be(true)
      expect(policy.show_profile_bookshelf_status?).to be(true)
      expect(policy.show_profile_jjaeks?).to be(true)
      expect(policy.write_profile_jjaek?).to be(true)
    end

    it "lets a following user view profile jjaeks but not write in the profile context" do
      user.active_follows.create!(followee: other_user)
      policy = described_class.new(user, other_user)

      expect(policy.profile_access_level).to eq(:following)
      expect(policy.show_profile_bookshelf?).to be(true)
      expect(policy.show_profile_bookshelf_status?).to be(false)
      expect(policy.show_profile_jjaeks?).to be(true)
      expect(policy.write_profile_jjaek?).to be(false)
    end

    it "lets an unrelated user view public profile jjaeks but not write in the profile context" do
      policy = described_class.new(user, other_user)

      expect(policy.profile_access_level).to eq(:none)
      expect(policy.show_profile_bookshelf?).to be(true)
      expect(policy.show_profile_bookshelf_status?).to be(false)
      expect(policy.show_profile_jjaeks?).to be(true)
      expect(policy.write_profile_jjaek?).to be(false)
    end

    it "gives a global admin profile and library read access without self mutation" do
      global_admin = User.create!(name: "Global admin", email: "user-policy-global-admin@example.com", password: "password123!", global_admin: true)
      policy = described_class.new(global_admin, other_user)

      expect(policy.profile_access_level).to eq(:none)
      expect(policy.show_profile_bookshelf?).to be(true)
      expect(policy.show_profile_bookshelf_status?).to be(true)
      expect(policy.show_library?).to be(true)
      expect(policy.write_profile_jjaek?).to be(false)
    end
  end
end
