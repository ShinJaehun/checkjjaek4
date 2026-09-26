require "rails_helper"

RSpec.describe Groups::SuspendOperation do
  let(:group_admin) { User.create!(name: "Group admin", email: "operation-suspend-owner@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Admin", email: "operation-suspend-admin@example.com", password: "password123!", global_admin: true) }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :public_group) }

  it "snapshots all active member IDs and schedules the created audit row" do
    normal_member = User.create!(name: "Normal", email: "operation-normal-member@example.com", password: "password123!")
    suspended_member = User.create!(name: "Activity suspended", email: "operation-suspended-member@example.com", password: "password123!")
    invited = User.create!(name: "Invited", email: "operation-invited-member@example.com", password: "password123!")
    pending = User.create!(name: "Pending", email: "operation-pending-member@example.com", password: "password123!")
    former_member = User.create!(name: "Former", email: "operation-former-member@example.com", password: "password123!")
    banned = User.create!(name: "Banned", email: "operation-banned-member@example.com", password: "password123!")
    group.group_memberships.create!(user: normal_member, status: :active)
    group.group_memberships.create!(user: suspended_member, status: :active, moderation_status: :activity_suspended)
    suspended_member.update!(suspended_at: Time.current)
    group.group_memberships.create!(user: invited, status: :invited)
    group.group_memberships.create!(user: pending, status: :pending)
    group.group_memberships.create!(user: former_member, status: :active).destroy!
    GroupMemberBan.create!(group:, user: banned)
    expect(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      expect(moderation_action).to have_attributes(target: group, actor: admin, action_type: "suspend_group_operation")
      expect(moderation_action).to be_persisted
      expect(recipient_ids).to match_array([ group_admin.id, normal_member.id, suspended_member.id ])
    end

    expect(described_class.new(group, actor: admin, public_reason: "other").call!).to eq(group)
  end

  it "atomically records the state and audit without changing lifecycle or membership" do
    lifecycle_status = group.lifecycle_status
    membership_ids = group.group_membership_ids

    described_class.new(group, actor: admin, public_reason: "repeated_policy_violations", internal_note: "Reviewed").call!
    action = group.current_operation_suspension_action

    expect(group.reload).to be_operation_suspended
    expect(group.lifecycle_status).to eq(lifecycle_status)
    expect(group.group_membership_ids).to eq(membership_ids)
    expect(action).to have_attributes(actor: admin, action_type: "suspend_group_operation", public_reason: "repeated_policy_violations", internal_note: "Reviewed")
  end

  it "rejects actors denied by the policy without changing state or audit" do
    expect {
      described_class.new(group, actor: group_admin, public_reason: "other").call!
    }.to raise_error(described_class::InvalidState)
    expect(group.reload).to be_operation_active
    expect(ModerationAction.where(target: group)).to be_empty
  end

  it "rejects free-text and blank reasons without changing state or audit" do
    ["Service safety", ""].each do |reason|
      expect {
        described_class.new(group, actor: admin, public_reason: reason).call!
      }.to raise_error(described_class::InvalidState)
    end

    expect(group.reload).to be_operation_active
    expect(ModerationAction.where(target: group)).to be_empty
  end

  it "rejects duplicate suspension without adding another audit" do
    described_class.new(group, actor: admin, public_reason: "other").call!
    expect {
      described_class.new(group, actor: admin, public_reason: "other").call!
    }.to raise_error(described_class::InvalidState)

    expect(group.reload).to be_operation_suspended
    expect(ModerationAction.where(target: group, action_type: :suspend_group_operation).count).to eq(1)
  end

  it "translates predefined reasons and preserves legacy free-text labels" do
    allow(I18n).to receive(:t).with("groups.operation_suspension_reasons.other").and_return("Other reason")

    expect(Group.suspension_reason_label("other")).to eq("Other reason")
    expect(Group.suspension_reason_label("Legacy free-text reason")).to eq("Legacy free-text reason")
  end

  it "does not change user suspension, member bans, or existing content" do
    member = User.create!(name: "Member", email: "operation-independent-member@example.com", password: "password123!")
    other = User.create!(name: "Other", email: "operation-independent-other@example.com", password: "password123!")
    membership = group.group_memberships.create!(user: member, status: :active)
    member.update!(suspended_at: Time.current)
    ban = GroupMemberBan.create!(group:, user: other)
    jjaek = group_admin.jjaeks.create!(group:, content: "Preserved")

    described_class.new(group, actor: admin, public_reason: "harassment_or_targeting").call!

    expect(membership.reload).to be_persisted
    expect(member.reload).to be_suspended
    expect(ban.reload).to be_persisted
    expect(jjaek.reload).to be_persisted
  end
end
