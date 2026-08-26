require "rails_helper"

RSpec.describe GroupMembershipPolicy do
  let(:owner) { User.create!(name: "Owner", email: "membership-policy-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:member) { User.create!(name: "Member", email: "membership-policy-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "membership-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group) }

  it "allows only the group owner to approve a pending membership" do
    membership = group.group_memberships.create!(user: member, status: :pending)

    expect(described_class.new(owner, membership).approve?).to be(true)
    expect(described_class.new(other_user, membership).approve?).to be(false)
  end

  it "blocks actions that create active participation unless the group is active" do
    private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Lifecycle", group_type: :private_group)
    invited = private_group.group_memberships.create!(user: member, status: :invited)
    inactive_member = private_group.group_memberships.create!(user: other_user, status: :active)
    inactive_member.update!(status: :inactive)
    private_group.update!(
      lifecycle_status: :inactive,
      closure_reason: "Test closure",
      closed_at: Time.current
    )
    expect(described_class.new(member, invited).accept?).to be(false)
    expect(described_class.new(owner, inactive_member).reactivate?).to be(false)
    expect(described_class.new(owner, private_group.group_memberships.build(user: User.new, status: :invited)).invite?).to be(false)
  end

  it "does not allow an active membership to be approved again" do
    membership = group.group_memberships.create!(user: member, status: :active)

    expect(described_class.new(owner, membership).approve?).to be(false)
  end

  it "allows users to destroy only their own non-owner membership" do
    membership = group.group_memberships.create!(user: member, status: :pending)
    owner_membership = group.group_memberships.find_by!(user: owner)

    expect(described_class.new(member, membership).destroy?).to be(true)
    expect(described_class.new(other_user, membership).destroy?).to be(false)
    expect(described_class.new(owner, owner_membership).destroy?).to be(false)

    membership.update_column(:status, GroupMembership.statuses[:inactive])
    expect(described_class.new(member, membership.reload).destroy?).to be(false)
  end

  it "allows only a private group owner to invite another user" do
    private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private", group_type: :private_group)
    invitation = private_group.group_memberships.build(user: member, status: :invited)

    expect(described_class.new(owner, invitation).invite?).to be(true)
    expect(described_class.new(other_user, invitation).invite?).to be(false)
    expect(described_class.new(owner, invitation.tap { |item| item.user = owner }).invite?).to be(false)
  end

  it "does not allow invitations in discoverable groups" do
    invitation = group.group_memberships.build(user: member, status: :invited)

    expect(described_class.new(owner, invitation).invite?).to be(false)
  end

  it "allows only the invitee to accept or decline an invitation" do
    private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private", group_type: :private_group)
    invitation = private_group.group_memberships.create!(user: member, status: :invited)

    expect(described_class.new(member, invitation).accept?).to be(true)
    expect(described_class.new(member, invitation).decline?).to be(true)
    expect(described_class.new(other_user, invitation).accept?).to be(false)
    expect(described_class.new(owner, invitation).decline?).to be(false)
  end

  it "allows only the owner to deactivate an active non-owner member" do
    membership = group.group_memberships.create!(user: member, status: :active)
    owner_membership = group.group_memberships.find_by!(user: owner)

    expect(described_class.new(owner, membership).deactivate?).to be(true)
    expect(described_class.new(other_user, membership).deactivate?).to be(false)
    expect(described_class.new(owner, owner_membership).deactivate?).to be(false)

    membership.update_column(:status, GroupMembership.statuses[:pending])
    expect(described_class.new(owner, membership.reload).deactivate?).to be(false)
    membership.update_column(:status, GroupMembership.statuses[:invited])
    expect(described_class.new(owner, membership.reload).deactivate?).to be(false)
  end

  it "allows only the owner to reactivate or remove an inactive non-owner member" do
    membership = group.group_memberships.create!(user: member, status: :active)
    membership.update!(status: :inactive)

    expect(described_class.new(owner, membership).reactivate?).to be(true)
    expect(described_class.new(owner, membership).remove?).to be(true)
    expect(described_class.new(other_user, membership).reactivate?).to be(false)
    expect(described_class.new(other_user, membership).remove?).to be(false)

    membership.update!(status: :active)
    expect(described_class.new(owner, membership).remove?).to be(false)
  end

  it "allows only an approval group owner to reject a pending request" do
    membership = group.group_memberships.create!(user: member, status: :pending)

    expect(described_class.new(owner, membership).reject?).to be(true)
    expect(described_class.new(other_user, membership).reject?).to be(false)

    membership.update!(status: :active)
    expect(described_class.new(owner, membership).reject?).to be(false)
  end

  it "allows only a private group owner to revoke an invitation" do
    private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private revoke", group_type: :private_group)
    invitation = private_group.group_memberships.create!(user: member, status: :invited)

    expect(described_class.new(owner, invitation).revoke?).to be(true)
    expect(described_class.new(other_user, invitation).revoke?).to be(false)

    invitation.update!(status: :active)
    expect(described_class.new(owner, invitation).revoke?).to be(false)
  end

  it "rejects and revokes only in the matching group type" do
    pending = Group.create!(lifecycle_status: :active, owner: owner, name: "Public pending", group_type: :public_group)
      .group_memberships.create!(user: member, status: :pending)
    invited = group.group_memberships.create!(user: other_user, status: :invited)

    expect(described_class.new(owner, pending).reject?).to be(false)
    expect(described_class.new(owner, invited).revoke?).to be(false)
  end
end
