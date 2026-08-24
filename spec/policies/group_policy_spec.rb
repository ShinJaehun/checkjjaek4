require "rails_helper"

RSpec.describe GroupPolicy do
  let(:owner) { User.create!(name: "Owner", email: "group-policy-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:viewer) { User.create!(name: "Viewer", email: "group-policy-viewer@example.com", password: "password123!", password_confirmation: "password123!") }

  describe "#show?" do
    it "allows signed-in users to view public and approval groups" do
      public_group = Group.create!(owner: owner, name: "Public", group_type: :public_group)
      approval_group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)

      expect(described_class.new(viewer, public_group).show?).to be(true)
      expect(described_class.new(viewer, approval_group).show?).to be(true)
    end

    it "allows active and inactive members to view a private group" do
      private_group = Group.create!(owner: owner, name: "Private", group_type: :private_group)

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
      private_group = Group.create!(owner: owner, name: "Invited", group_type: :private_group)
      private_group.group_memberships.create!(user: viewer, status: :invited)

      policy = described_class.new(viewer, private_group)
      expect(policy.show?).to be(false)
      expect(policy.read_jjaeks?).to be(false)
    end
  end

  describe described_class::Scope do
    it "includes discoverable groups and active or inactive private groups" do
      public_group = Group.create!(owner: owner, name: "Public", group_type: :public_group)
      approval_group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)
      joined_private_group = Group.create!(owner: owner, name: "Joined private", group_type: :private_group)
      hidden_private_group = Group.create!(owner: owner, name: "Hidden private", group_type: :private_group)
      inactive_private_group = Group.create!(owner: owner, name: "Inactive private", group_type: :private_group)
      invited_private_group = Group.create!(owner: owner, name: "Invited private", group_type: :private_group)
      joined_private_group.group_memberships.create!(user: viewer, status: :active)
      inactive_private_group.group_memberships.create!(user: viewer, status: :inactive)
      invited_private_group.group_memberships.create!(user: viewer, status: :invited)

      resolved = described_class.new(viewer, Group.all).resolve

      expect(resolved).to include(public_group, approval_group, joined_private_group, inactive_private_group)
      expect(resolved).not_to include(hidden_private_group, invited_private_group)
    end
  end

  it "allows a signed-in user to create a private group" do
    private_group = Group.new(owner: viewer, name: "Private", group_type: :private_group)

    expect(described_class.new(viewer, private_group).create?).to be(true)
  end

  describe "#edit? and #update?" do
    it "allows only the owner" do
      group = Group.create!(owner: owner, name: "Managed", group_type: :public_group)
      group.group_memberships.create!(user: viewer, status: :active)
      nonmember = User.create!(name: "Nonmember", email: "group-policy-nonmember@example.com", password: "password123!", password_confirmation: "password123!")

      expect(described_class.new(owner, group).edit?).to be(true)
      expect(described_class.new(owner, group).update?).to be(true)
      expect(described_class.new(viewer, group).update?).to be(false)
      expect(described_class.new(nonmember, group).edit?).to be(false)
    end
  end
end
