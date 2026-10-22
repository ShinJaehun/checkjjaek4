require "rails_helper"

RSpec.describe GroupListHiding, type: :model do
  let!(:owner) { User.create!(name: "Owner", email: "hiding-owner@example.com", password: "password123!") }
  let!(:user) { User.create!(name: "Reader", email: "hiding-reader@example.com", password: "password123!") }
  let!(:group) { Group.create!(group_admin: owner, name: "Club", lifecycle_status: :active) }
  let!(:membership) { group.group_memberships.create!(user:, status: :active) }

  def hide_group
    described_class.create!(user:, group:)
  end

  it "enforces one hiding per user and group in the model and database" do
    hide_group
    expect(described_class.new(user:, group:)).not_to be_valid
    expect do
      described_class.transaction(requires_new: true) do
        described_class.insert_all!([ { user_id: user.id, group_id: group.id, created_at: Time.current, updated_at: Time.current } ])
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "clears the setting as soon as operation is restored and does not hide again on another suspension" do
    admin = User.create!(name: "Admin", email: "hiding-admin@example.com", password: "password123!", global_admin: true)
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other").call!
    hide_group
    Groups::RestoreOperation.new(group, actor: admin, public_reason: "Restored").call!
    expect(described_class.exists?(user:, group:)).to be(false)
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other").call!
    expect(described_class.exists?(user:, group:)).to be(false)
    expect(membership.reload).to be_active
    expect(ModerationAction.where(target: group).count).to eq(3)
  end

  it "waits for every restriction to be lifted before automatically restoring the entry" do
    membership.update!(moderation_status: :activity_suspended)
    group.update!(operation_suspended_at: Time.current)
    hide_group
    group.update!(operation_suspended_at: nil)
    expect(described_class.exists?(user:, group:)).to be(true)
    membership.update!(moderation_status: :normal)
    expect(described_class.exists?(user:, group:)).to be(false)
    membership.update!(moderation_status: :activity_suspended)
    expect(described_class.exists?(user:, group:)).to be(false)
  end

  it "clears a hidden closed group only upon reactivation approval with active membership" do
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    hide_group
    group.update!(lifecycle_status: :pending_approval)
    expect(described_class.exists?(user:, group:)).to be(true)
    group.active!
    expect(described_class.exists?(user:, group:)).to be(false)
    expect(membership.reload).to be_active
    expect(group.closed_at).to be_present
    expect(group.closure_reason).to eq("Closed")
  end

  it "restores an activity-suspended member through the existing audited operation" do
    GroupMemberships::SuspendActivity.new(membership, actor: owner, public_reason: "Rules").call!
    hide_group
    GroupMemberships::RestoreActivity.new(membership, actor: owner, public_reason: "Restored").call!
    expect(described_class.exists?(user:, group:)).to be(false)
    expect(membership.reload).to be_active
    expect(ModerationAction.where(target: membership).count).to eq(2)
  end

  it "keeps a former member hidden across reopening and clears the setting upon rejoining" do
    membership.destroy!
    group.group_membership_events.create!(user:, actor: user, event_type: :left)
    hide_group
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    group.update!(lifecycle_status: :pending_approval)
    group.active!
    expect(described_class.exists?(user:, group:)).to be(true)
    group.group_memberships.create!(user:, status: :active)
    expect(described_class.exists?(user:, group:)).to be(false)
    expect(group.group_membership_events.where(user:, event_type: :left)).to exist
  end

  it "keeps a ban hiding after unban and pending/invited membership until active again" do
    ban = GroupMemberBans::Ban.new(membership, actor: owner, public_reason: "Rules").call!
    hide_group
    GroupMemberBans::Unban.new(ban, actor: owner, public_reason: "Unbanned").call!
    expect(described_class.exists?(user:, group:)).to be(true)
    expect(group.group_memberships.where(user:)).not_to exist
    states = GroupMembershipEvent.past_states_for(user:, groups: [ group ])
    expect(states.fetch(group.id).fetch(:status)).to eq("former")
    invitation = group.group_memberships.create!(user:, status: :invited)
    expect(described_class.exists?(user:, group:)).to be(true)
    invitation.active!
    expect(described_class.exists?(user:, group:)).to be(false)
    expect(ModerationAction.where(membership_group_id: group.id, membership_user_id: user.id).count).to eq(2)
  end

  it "rolls back automatic restoration with a failed eligibility transaction" do
    membership.update!(moderation_status: :activity_suspended)
    hiding = hide_group
    expect do
      GroupMembership.transaction do
        membership.update!(moderation_status: :normal)
        expect(described_class.exists?(hiding.id)).to be(false)
        raise ActiveRecord::RecordInvalid.new(membership)
      end
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(membership.reload).to be_activity_suspended
    expect(described_class.exists?(hiding.id)).to be(true)
  end

  it "rolls back hiding removal together with a failed group restoration" do
    group.update!(operation_suspended_at: Time.current)
    hiding = hide_group
    Group.transaction do
      group.update!(operation_suspended_at: nil)
      expect(described_class.exists?(hiding.id)).to be(false)
      raise ActiveRecord::Rollback
    end
    expect(group.reload).to be_operation_suspended
    expect(described_class.exists?(hiding.id)).to be(true)
  end
end
