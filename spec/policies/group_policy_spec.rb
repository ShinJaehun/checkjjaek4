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

    it "allows only active members to view a private group" do
      private_group = Group.create!(owner: owner, name: "Private", group_type: :private_group)

      expect(described_class.new(viewer, private_group).show?).to be(false)

      private_group.group_memberships.create!(user: viewer, status: :active)
      expect(described_class.new(viewer, private_group).show?).to be(true)
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
    it "includes discoverable groups and joined private groups" do
      public_group = Group.create!(owner: owner, name: "Public", group_type: :public_group)
      approval_group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)
      joined_private_group = Group.create!(owner: owner, name: "Joined private", group_type: :private_group)
      hidden_private_group = Group.create!(owner: owner, name: "Hidden private", group_type: :private_group)
      joined_private_group.group_memberships.create!(user: viewer, status: :active)

      resolved = described_class.new(viewer, Group.all).resolve

      expect(resolved).to include(public_group, approval_group, joined_private_group)
      expect(resolved).not_to include(hidden_private_group)
    end
  end

  it "allows a signed-in user to create a private group" do
    private_group = Group.new(owner: viewer, name: "Private", group_type: :private_group)

    expect(described_class.new(viewer, private_group).create?).to be(true)
  end
end
