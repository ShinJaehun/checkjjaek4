require "rails_helper"

RSpec.describe GroupPolicy do
  let(:group_admin) { User.create!(name: "Group admin", email: "group-policy-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:viewer) { User.create!(name: "Viewer", email: "group-policy-viewer@example.com", password: "password123!", password_confirmation: "password123!") }

  it "limits admin inventory scope to global admins" do
    admin = User.create!(name: "Admin", email: "inventory-policy-admin@example.com", password: "password123!", global_admin: true)
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private inventory", group_type: :private_group)

    expect(described_class::AdminInventoryScope.new(admin, Group.all).resolve).to include(group)
    expect(described_class::AdminInventoryScope.new(viewer, Group.all).resolve).to be_empty
  end

  describe "#show?" do
    it "allows signed-in users to view public and approval groups" do
      public_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
      approval_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)

      expect(described_class.new(viewer, public_group).show?).to be(true)
      expect(described_class.new(viewer, approval_group).show?).to be(true)
    end

    it "allows active and inactive members to view a private group" do
      private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)

      expect(described_class.new(viewer, private_group).show?).to be(false)

      private_group.group_memberships.create!(user: viewer, status: :active)
      active_policy = described_class.new(viewer, private_group)
      expect(active_policy.show?).to be(true)
      expect(active_policy.read_jjaeks?).to be(true)
      expect(active_policy.create_jjaek?).to be(true)

      private_group.group_memberships.find_by!(user: viewer).update!(status: :inactive)
      policy = described_class.new(viewer, private_group)
      expect(policy.show?).to be(true)
      expect(policy.read_jjaeks?).to be(false)
      expect(policy.create_jjaek?).to be(false)
    end

    it "does not treat an invitation as private group access" do
      private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Invited", group_type: :private_group)
      private_group.group_memberships.create!(user: viewer, status: :invited)

      policy = described_class.new(viewer, private_group)
      expect(policy.show?).to be(false)
      expect(policy.read_jjaeks?).to be(false)
    end
  end

  describe "lifecycle access" do
    it "shows pending groups only to their group_admin" do
      group = Group.create!(group_admin: group_admin, name: "Pending", group_type: :public_group, application_purpose: "Read together")

      expect(described_class.new(group_admin, group).show?).to be(true)
      expect(described_class.new(viewer, group).show?).to be(false)
      expect(described_class.new(group_admin, group).read_jjaeks?).to be(false)
    end

    it "lets active members read an inactive group without exposing it to nonmembers" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Closed", group_type: :public_group)
      group.group_memberships.create!(user: viewer, status: :active)
      group.update!(
        lifecycle_status: :inactive,
        closure_reason: "Test closure",
        closed_at: Time.current
      )
      nonmember = User.create!(name: "Nonmember", email: "closed-group-nonmember@example.com", password: "password123!", password_confirmation: "password123!")

      expect(described_class.new(viewer, group).show?).to be(true)
      expect(described_class.new(viewer, group).read_jjaeks?).to be(true)
      expect(described_class.new(viewer, group).create_jjaek?).to be(false)
      expect(described_class.new(nonmember, group).show?).to be(false)
    end
  end

  describe described_class::Scope do
    it "includes discoverable groups and active or inactive private groups" do
      public_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
      approval_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
      joined_private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Joined private", group_type: :private_group)
      hidden_private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Hidden private", group_type: :private_group)
      inactive_private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Inactive private", group_type: :private_group)
      invited_private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Invited private", group_type: :private_group)
      joined_private_group.group_memberships.create!(user: viewer, status: :active)
      inactive_private_group.group_memberships.create!(user: viewer, status: :inactive)
      invited_private_group.group_memberships.create!(user: viewer, status: :invited)

      resolved = described_class.new(viewer, Group.all).resolve

      expect(resolved).to include(public_group, approval_group, joined_private_group, inactive_private_group)
      expect(resolved).not_to include(hidden_private_group, invited_private_group)
    end

    it "keeps pending and inactive groups out of general discovery" do
      pending = Group.create!(group_admin: group_admin, name: "Pending", group_type: :public_group, application_purpose: "Read together")
      inactive = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Inactive", group_type: :public_group)
      inactive.update!(
        lifecycle_status: :inactive,
        closure_reason: "Test closure",
        closed_at: Time.current
      )
      expect(described_class.new(viewer, Group.all).resolve).not_to include(pending, inactive)
      expect(described_class.new(group_admin, Group.all).resolve).to include(pending, inactive)
    end
  end

  it "allows a signed-in user to create a private group" do
    private_group = Group.new(group_admin: viewer, name: "Private", group_type: :private_group)

    expect(described_class.new(viewer, private_group).create?).to be(true)
  end

  describe "#edit? and #update?" do
    it "allows only the group_admin" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Managed", group_type: :public_group)
      group.group_memberships.create!(user: viewer, status: :active)
      nonmember = User.create!(name: "Nonmember", email: "group-policy-nonmember@example.com", password: "password123!", password_confirmation: "password123!")

      expect(described_class.new(group_admin, group).edit?).to be(true)
      expect(described_class.new(group_admin, group).update?).to be(true)
      expect(described_class.new(viewer, group).update?).to be(false)
      expect(described_class.new(nonmember, group).edit?).to be(false)
    end
  end

  describe "#view_members?" do
    it "allows only the group admin and global admin" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Members", group_type: :public_group)
      admin = User.create!(name: "Global admin", email: "member-policy-admin@example.com", password: "password123!", global_admin: true)

      expect(described_class.new(group_admin, group).view_members?).to be(true)
      expect(described_class.new(admin, group).view_members?).to be(true)
      expect(described_class.new(viewer, group).view_members?).to be(false)
    end
  end

  describe "#transfer_admin?" do
    it "allows the current admin and global admin for active or inactive groups" do
      admin = User.create!(name: "Global admin", email: "transfer-policy-admin@example.com", password: "password123!", password_confirmation: "password123!", global_admin: true)
      active = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Active", group_type: :public_group)
      inactive = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Inactive", group_type: :public_group)
      inactive.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)
      pending = Group.create!(group_admin: group_admin, name: "Pending", group_type: :public_group, application_purpose: "Read together")
      active.group_memberships.create!(user: viewer, status: :active)

      expect(described_class.new(group_admin, active).transfer_admin?).to be(true)
      expect(described_class.new(group_admin, inactive).transfer_admin?).to be(true)
      expect(described_class.new(group_admin, pending).transfer_admin?).to be(false)
      expect(described_class.new(viewer, active).transfer_admin?).to be(false)
      expect(described_class.new(admin, active).transfer_admin?).to be(true)
      expect(described_class.new(admin, inactive).transfer_admin?).to be(true)
      expect(described_class.new(admin, pending).transfer_admin?).to be(false)
    end
  end

  it "gives a global admin operational investigation without general group lifecycle actions" do
    admin = User.create!(name: "Admin", email: "policy-global-admin@example.com", password: "password123!", password_confirmation: "password123!", global_admin: true)
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Group admin managed", group_type: :private_group)
    policy = described_class.new(admin, group)

    expect(policy.view_admin_details?).to be(true)
    expect(policy.view_admin_inventory?).to be(true)
    expect(policy.edit?).to be(false)
    expect(policy.update?).to be(false)
    expect(policy.close?).to be(false)
    expect(policy.request_reactivation?).to be(false)
    expect(policy.show?).to be(true)
    expect(policy.read_jjaeks?).to be(true)
    expect(policy.create_jjaek?).to be(false)
  end

  it "includes every group in the general scope for a global admin" do
    admin = User.create!(name: "Admin", email: "policy-scope-admin@example.com", password: "password123!", global_admin: true)
    public_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    pending_group = Group.create!(group_admin: group_admin, name: "Pending", group_type: :approval_group, application_purpose: "Read together")
    inactive_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Inactive", group_type: :private_group)
    inactive_group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)

    resolved = described_class::Scope.new(admin, Group.all).resolve

    expect(resolved).to include(public_group, private_group, pending_group, inactive_group)
  end
end
