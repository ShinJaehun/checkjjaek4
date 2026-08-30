require "rails_helper"

RSpec.describe Groups::SuspendOperation do
  let(:group_admin) { User.create!(name: "Group admin", email: "operation-suspend-owner@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Admin", email: "operation-suspend-admin@example.com", password: "password123!", global_admin: true) }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :public_group) }

  it "atomically records the state and audit without changing lifecycle or membership" do
    lifecycle_status = group.lifecycle_status
    membership_ids = group.group_membership_ids

    described_class.new(group, actor: admin, public_reason: "Service safety", internal_note: "Reviewed").call!
    action = group.current_operation_suspension_action

    expect(group.reload).to be_operation_suspended
    expect(group.lifecycle_status).to eq(lifecycle_status)
    expect(group.group_membership_ids).to eq(membership_ids)
    expect(action).to have_attributes(actor: admin, action_type: "suspend_group_operation", public_reason: "Service safety", internal_note: "Reviewed")
  end

  it "rejects non-global admins, duplicate suspension, and invalid audits without partial state" do
    expect {
      described_class.new(group, actor: group_admin, public_reason: "No").call!
    }.to raise_error(described_class::InvalidState)
    expect(group.reload).to be_operation_active

    expect {
      described_class.new(group, actor: admin, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(group.reload).to be_operation_active

    described_class.new(group, actor: admin, public_reason: "First").call!
    expect {
      described_class.new(group, actor: admin, public_reason: "Again").call!
    }.to raise_error(described_class::InvalidState)
  end

  it "does not change user suspension, member bans, or existing content" do
    member = User.create!(name: "Member", email: "operation-independent-member@example.com", password: "password123!")
    other = User.create!(name: "Other", email: "operation-independent-other@example.com", password: "password123!")
    membership = group.group_memberships.create!(user: member, status: :active)
    member.update!(suspended_at: Time.current)
    ban = GroupMemberBan.create!(group:, user: other)
    jjaek = group_admin.jjaeks.create!(group:, content: "Preserved")

    described_class.new(group, actor: admin, public_reason: "Service safety").call!

    expect(membership.reload).to be_persisted
    expect(member.reload).to be_suspended
    expect(ban.reload).to be_persisted
    expect(jjaek.reload).to be_persisted
  end
end
