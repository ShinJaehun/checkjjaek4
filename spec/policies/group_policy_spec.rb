require "rails_helper"

RSpec.describe GroupPolicy do
  let(:owner) { User.create!(name: "Owner", email: "group-policy-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:viewer) { User.create!(name: "Viewer", email: "group-policy-viewer@example.com", password: "password123!", password_confirmation: "password123!") }

  describe "#show?" do
    it "allows signed-in users to view public and approval groups" do
      public_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
      approval_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)

      expect(described_class.new(viewer, public_group).show?).to be(true)
      expect(described_class.new(viewer, approval_group).show?).to be(true)
    end

    it "allows active and inactive members to view a private group" do
      private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private", group_type: :private_group)

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
      private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Invited", group_type: :private_group)
      private_group.group_memberships.create!(user: viewer, status: :invited)

      policy = described_class.new(viewer, private_group)
      expect(policy.show?).to be(false)
      expect(policy.read_jjaeks?).to be(false)
    end
  end

  describe "lifecycle access" do
    it "shows pending groups only to their owner" do
      group = Group.create!(owner: owner, name: "Pending", group_type: :public_group, application_purpose: "Read together")

      expect(described_class.new(owner, group).show?).to be(true)
      expect(described_class.new(viewer, group).show?).to be(false)
      expect(described_class.new(owner, group).read_jjaeks?).to be(false)
    end

    it "lets active members read an inactive group without exposing it to nonmembers" do
      group = Group.create!(lifecycle_status: :active, owner: owner, name: "Closed", group_type: :public_group)
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
      public_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
      approval_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)
      joined_private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Joined private", group_type: :private_group)
      hidden_private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Hidden private", group_type: :private_group)
      inactive_private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Inactive private", group_type: :private_group)
      invited_private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Invited private", group_type: :private_group)
      joined_private_group.group_memberships.create!(user: viewer, status: :active)
      inactive_private_group.group_memberships.create!(user: viewer, status: :inactive)
      invited_private_group.group_memberships.create!(user: viewer, status: :invited)

      resolved = described_class.new(viewer, Group.all).resolve

      expect(resolved).to include(public_group, approval_group, joined_private_group, inactive_private_group)
      expect(resolved).not_to include(hidden_private_group, invited_private_group)
    end

    it "keeps pending and inactive groups out of general discovery" do
      pending = Group.create!(owner: owner, name: "Pending", group_type: :public_group, application_purpose: "Read together")
      inactive = Group.create!(lifecycle_status: :active, owner: owner, name: "Inactive", group_type: :public_group)
      inactive.update!(
        lifecycle_status: :inactive,
        closure_reason: "Test closure",
        closed_at: Time.current
      )
      expect(described_class.new(viewer, Group.all).resolve).not_to include(pending, inactive)
      expect(described_class.new(owner, Group.all).resolve).to include(pending, inactive)
    end
  end

  it "allows a signed-in user to create a private group" do
    private_group = Group.new(owner: viewer, name: "Private", group_type: :private_group)

    expect(described_class.new(viewer, private_group).create?).to be(true)
  end

  describe "#edit? and #update?" do
    it "allows only the owner" do
      group = Group.create!(lifecycle_status: :active, owner: owner, name: "Managed", group_type: :public_group)
      group.group_memberships.create!(user: viewer, status: :active)
      nonmember = User.create!(name: "Nonmember", email: "group-policy-nonmember@example.com", password: "password123!", password_confirmation: "password123!")

      expect(described_class.new(owner, group).edit?).to be(true)
      expect(described_class.new(owner, group).update?).to be(true)
      expect(described_class.new(viewer, group).update?).to be(false)
      expect(described_class.new(nonmember, group).edit?).to be(false)
    end
  end
end
