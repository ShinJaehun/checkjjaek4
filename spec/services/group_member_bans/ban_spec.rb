require "rails_helper"

RSpec.describe GroupMemberBans::Ban do
  let(:group_admin) { User.create!(name: "Admin", email: "ban-service-admin@example.com", password: "password123!") }
  let(:member) { User.create!(name: "Member", email: "ban-service-member@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Bans", group_type: :public_group) }

  it "bans active and activity-suspended memberships" do
    active = group.group_memberships.create!(user: member, status: :active)
    ban = described_class.new(active, actor: group_admin, public_reason: "Rule").call!
    expect(ban).to have_attributes(group:, user: member)
    expect(GroupMembership.exists?(active.id)).to be(false)

    suspended_member = User.create!(name: "Suspended member", email: "ban-suspended@example.com", password: "password123!")
    suspended = group.group_memberships.create!(user: suspended_member, status: :active)
    GroupMemberships::SuspendActivity.new(suspended, actor: group_admin, public_reason: "Suspended").call!
    suspension = suspended.current_activity_suspension_action

    described_class.new(suspended, actor: group_admin, public_reason: "Ban").call!
    expect(ModerationAction.exists?(suspension.id)).to be(true)
    expect(suspended_member.reload).not_to be_suspended
  end

  it "rejects pending and invited memberships without changing them" do
    %i[pending invited].each_with_index do |status, index|
      target = User.create!(
        name: status.to_s,
        email: "ban-state-#{index}@example.com",
        password: "password123!"
      )
      membership = group.group_memberships.create!(user: target, status:)

      expect {
        described_class.new(membership, actor: group_admin, public_reason: "Rule").call!
      }.to raise_error(described_class::InvalidState)

      expect(membership.reload.status).to eq(status.to_s)
      expect(GroupMemberBan.exists?(group:, user: target)).to be(false)
    end
   end

  it "creates an attributed audit, clears removal UX, and does not record ordinary removal" do
    membership = group.group_memberships.create!(user: member, status: :active)
    GroupMembershipRemoval.create!(group:, user: member, removed_by: group_admin)
    removed_count = group.group_membership_events.removed.count

    ban = described_class.new(
      membership,
      actor: group_admin,
      public_reason: "Public reason",
      internal_note: "Internal note"
    ).call!
    action = ban.current_ban_action

    expect(action).to have_attributes(
      action_type: "ban_from_group",
      actor: group_admin,
      public_reason: "Public reason",
      internal_note: "Internal note",
      membership_group_id: group.id,
      membership_user_id: member.id
    )
    expect(GroupMembershipRemoval.exists?(group:, user: member)).to be(false)
    expect(group.group_membership_events.removed.count).to eq(removed_count)
  end

  it "rolls back the marker and membership deletion when the audit is invalid" do
    membership = group.group_memberships.create!(user: member, status: :active)

    expect {
      described_class.new(membership, actor: group_admin, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(GroupMemberBan.exists?(group:, user: member)).to be(false)
    expect(GroupMembership.exists?(membership.id)).to be(true)
  end

  it "rejects non-admin actors and the group admin membership" do
    membership = group.group_memberships.create!(user: member, status: :active)
    outsider = User.create!(name: "Outsider", email: "ban-service-outsider@example.com", password: "password123!")

    expect {
      described_class.new(membership, actor: outsider, public_reason: "Blocked").call!
    }.to raise_error(described_class::InvalidState)
    expect {
      described_class.new(group.group_memberships.find_by!(user: group_admin), actor: group_admin, public_reason: "Blocked").call!
    }.to raise_error(described_class::InvalidState)
  end
end
