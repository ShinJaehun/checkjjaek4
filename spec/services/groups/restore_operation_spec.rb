require "rails_helper"

RSpec.describe Groups::RestoreOperation do
  let(:group_admin) { User.create!(name: "Group admin", email: "operation-restore-owner@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Admin", email: "operation-restore-admin@example.com", password: "password123!", global_admin: true) }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :public_group) }

  it "atomically records a reversal and restores only operation state" do
    membership_ids = group.group_membership_ids
    jjaek = group_admin.jjaeks.create!(group:, content: "Preserved")
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other").call!
    original = group.current_operation_suspension_action

    described_class.new(group, actor: admin, public_reason: "Resolved after review", internal_note: "Checked").call!
    reversal = ModerationAction.find_by!(reversal_of: original)

    expect(group.reload).to be_operation_active
    expect(group).to be_active
    expect(group.group_membership_ids).to eq(membership_ids)
    expect(jjaek.reload).to be_persisted
    expect(reversal).to have_attributes(action_type: "restore_group_operation", public_reason: "Resolved after review", internal_note: "Checked")
    expect(original.reload.public_reason).to eq("other")
  end

  it "rejects a normal group and rolls back when the reversal audit is invalid" do
    expect {
      described_class.new(group, actor: admin, public_reason: "No suspension").call!
    }.to raise_error(described_class::InvalidState)

    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other").call!
    expect {
      described_class.new(group, actor: admin, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(group.reload).to be_operation_suspended
    expect(ModerationAction.where(target: group, action_type: :restore_group_operation)).to be_empty
  end

  it "rejects actors denied by the policy without changing state or audit" do
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other").call!

    expect {
      described_class.new(group, actor: group_admin, public_reason: "Resolved").call!
    }.to raise_error(described_class::InvalidState)

    expect(group.reload).to be_operation_suspended
    expect(ModerationAction.where(target: group, action_type: :restore_group_operation)).to be_empty
  end

  it "supports repeated suspend and restore cycles and resolves only the current suspension" do
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "repeated_policy_violations").call!
    first = group.current_operation_suspension_action
    described_class.new(group, actor: admin, public_reason: "First resolved").call!
    expect(group.current_operation_suspension_action).to be_nil

    Groups::SuspendOperation.new(group, actor: admin, public_reason: "facilitating_violations").call!
    second = group.current_operation_suspension_action
    expect(second).not_to eq(first)
    expect(second.public_reason).to eq("facilitating_violations")

    described_class.new(group, actor: admin, public_reason: "Second resolved").call!
    expect(group.current_operation_suspension_action).to be_nil
    expect(ModerationAction.where(target: group, action_type: :restore_group_operation).count).to eq(2)
  end
end
