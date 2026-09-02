require "rails_helper"

RSpec.describe GroupMembershipPolicy do
  let(:group_admin) { User.create!(name: "Group admin", email: "membership-policy-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:member) { User.create!(name: "Member", email: "membership-policy-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "membership-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group) }

  it "allows only the group group_admin to approve a pending membership" do
    membership = group.group_memberships.create!(user: member, status: :pending)

    expect(described_class.new(group_admin, membership).approve?).to be(true)
    expect(described_class.new(other_user, membership).approve?).to be(false)
  end

  it "does not grant general membership management to a global admin" do
    global_admin = User.create!(name: "Global admin", email: "membership-global-admin@example.com", password: "password123!", global_admin: true)
    membership = group.group_memberships.create!(user: member, status: :pending)

    policy = described_class.new(global_admin, membership)

    expect(policy.approve?).to be(false)
    expect(policy.reject?).to be(false)
    expect(policy.remove?).to be(false)
    expect(policy.suspend_activity?).to be(false)
    expect(policy.restore_activity?).to be(false)
    expect(policy.ban_from_group?).to be(false)
  end

  it "allows only the group admin to moderate an ordinary active member" do
    global_admin = User.create!(name: "Global moderator", email: "membership-moderator@example.com", password: "password123!", global_admin: true)
    peer = User.create!(name: "Peer", email: "membership-peer@example.com", password: "password123!")
    membership = group.group_memberships.create!(user: member, status: :active)
    group.group_memberships.create!(user: peer, status: :active)

    expect(described_class.new(group_admin, membership).suspend_activity?).to be(true)
    expect(described_class.new(global_admin, membership).suspend_activity?).to be(false)
    expect(described_class.new(peer, membership).suspend_activity?).to be(false)
    expect(described_class.new(other_user, membership).suspend_activity?).to be(false)

    membership.update!(moderation_status: :activity_suspended)
    expect(described_class.new(group_admin, membership).suspend_activity?).to be(false)
    expect(described_class.new(group_admin, membership).restore_activity?).to be(true)
    expect(described_class.new(global_admin, membership).restore_activity?).to be(false)
    expect(described_class.new(group_admin, membership).ban_from_group?).to be(true)
    expect(described_class.new(global_admin, membership).ban_from_group?).to be(false)
  end

  it "does not moderate the group admin or non-active memberships" do
    group_admin_membership = group.group_memberships.find_by!(user: group_admin)

    expect(described_class.new(group_admin, group_admin_membership).suspend_activity?).to be(false)

    %i[pending invited].each_with_index do |status, index|
      target = User.create!(name: status.to_s, email: "membership-state-#{index}@example.com", password: "password123!")
      membership = group.group_memberships.create!(user: target, status:)

      expect(described_class.new(group_admin, membership).suspend_activity?).to be(false)
      expect(described_class.new(group_admin, membership).restore_activity?).to be(false)
      expect(described_class.new(group_admin, membership).ban_from_group?).to be(false)
    end
  end

  it "blocks actions that create active participation unless the group is active" do
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Lifecycle", group_type: :private_group)
    invited = private_group.group_memberships.create!(user: member, status: :invited)
    private_group.update!(
      lifecycle_status: :inactive,
      closure_reason: "Test closure",
      closed_at: Time.current
    )
    expect(described_class.new(member, invited).accept?).to be(false)
    expect(described_class.new(group_admin, private_group.group_memberships.build(user: User.new, status: :invited)).invite?).to be(false)
  end

  it "does not allow an active membership to be approved again" do
    membership = group.group_memberships.create!(user: member, status: :active)

    expect(described_class.new(group_admin, membership).approve?).to be(false)
  end

  it "allows users to destroy only their own non-group_admin membership" do
    membership = group.group_memberships.create!(user: member, status: :pending)
    group_admin_membership = group.group_memberships.find_by!(user: group_admin)

    expect(described_class.new(member, membership).destroy?).to be(true)
    expect(described_class.new(other_user, membership).destroy?).to be(false)
    expect(described_class.new(group_admin, group_admin_membership).destroy?).to be(false)
  end

  it "allows only a private group group_admin to invite another user" do
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    invitation = private_group.group_memberships.build(user: member, status: :invited)

    expect(described_class.new(group_admin, invitation).invite?).to be(true)
    expect(described_class.new(other_user, invitation).invite?).to be(false)
    expect(described_class.new(group_admin, invitation.tap { |item| item.user = group_admin }).invite?).to be(false)
  end

  it "does not allow invitations in discoverable groups" do
    invitation = group.group_memberships.build(user: member, status: :invited)

    expect(described_class.new(group_admin, invitation).invite?).to be(false)
  end

  it "allows only the invitee to accept or decline an invitation" do
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    invitation = private_group.group_memberships.create!(user: member, status: :invited)

    expect(described_class.new(member, invitation).accept?).to be(true)
    expect(described_class.new(member, invitation).decline?).to be(true)
    expect(described_class.new(other_user, invitation).accept?).to be(false)
    expect(described_class.new(group_admin, invitation).decline?).to be(false)
  end

  it "allows only the group_admin to remove an active non-group_admin member" do
    membership = group.group_memberships.create!(user: member, status: :active)
    group_admin_membership = group.group_memberships.find_by!(user: group_admin)

    expect(described_class.new(group_admin, membership).remove?).to be(true)
    expect(described_class.new(other_user, membership).remove?).to be(false)
    expect(described_class.new(group_admin, group_admin_membership).remove?).to be(false)

    membership.update_column(:status, GroupMembership.statuses[:pending])
    expect(described_class.new(group_admin, membership.reload).remove?).to be(false)
    membership.update_column(:status, GroupMembership.statuses[:invited])
    expect(described_class.new(group_admin, membership).remove?).to be(false)
  end

  it "allows only an approval group group_admin to reject a pending request" do
    membership = group.group_memberships.create!(user: member, status: :pending)

    expect(described_class.new(group_admin, membership).reject?).to be(true)
    expect(described_class.new(other_user, membership).reject?).to be(false)

    membership.update!(status: :active)
    expect(described_class.new(group_admin, membership).reject?).to be(false)
  end

  it "allows only a private group group_admin to revoke an invitation" do
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private revoke", group_type: :private_group)
    invitation = private_group.group_memberships.create!(user: member, status: :invited)

    expect(described_class.new(group_admin, invitation).revoke?).to be(true)
    expect(described_class.new(other_user, invitation).revoke?).to be(false)

    invitation.update!(status: :active)
    expect(described_class.new(group_admin, invitation).revoke?).to be(false)
  end

  it "rejects and revokes only in the matching group type" do
    pending = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public pending", group_type: :public_group)
      .group_memberships.create!(user: member, status: :pending)
    invited = group.group_memberships.create!(user: other_user, status: :invited)

    expect(described_class.new(group_admin, pending).reject?).to be(false)
    expect(described_class.new(group_admin, invited).revoke?).to be(false)
  end

  it "blocks participation and group-admin membership mutations while group operation is suspended" do
    membership = group.group_memberships.create!(user: member, status: :pending)
    group.update!(operation_suspended_at: Time.current)

    policy = described_class.new(group_admin, membership)
    expect(described_class.new(member, membership)).not_to be_create
    expect(policy).not_to be_approve
    expect(policy).not_to be_reject
    expect(policy).not_to be_remove
    expect(policy).not_to be_suspend_activity
    expect(policy).not_to be_ban_from_group
  end
end
