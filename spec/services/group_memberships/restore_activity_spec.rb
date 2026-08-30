require "rails_helper"

RSpec.describe GroupMemberships::RestoreActivity do
  let(:group_admin) { User.create!(name: "Admin", email: "activity-restore-admin@example.com", password: "password123!") }
  let(:member) { User.create!(name: "Member", email: "activity-restore-member@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :approval_group) }
  let(:membership) { group.group_memberships.create!(user: member, status: :active, moderation_status: :activity_suspended) }
  let!(:suspension) do
    ModerationAction.create!(target: membership, actor: group_admin, action_type: :suspend_activity, public_reason: "Original")
  end

  it "restores activity with a separate audit action linked to the suspension" do
    described_class.new(membership, actor: group_admin, public_reason: "Resolved", internal_note: "Reviewed").call!

    restore = ModerationAction.order(:id).last
    expect(membership.reload).to be_moderation_status_normal
    expect(membership).to be_active
    expect(member.reload).not_to be_suspended
    expect(restore).to have_attributes(
      action_type: "restore_activity",
      reversal_of: suspension,
      public_reason: "Resolved",
      internal_note: "Reviewed",
      membership_group_id: group.id,
      membership_user_id: member.id
    )
    expect(restore.attributes.values_at("membership_group_id", "membership_user_id")).to eq(
      suspension.attributes.values_at("membership_group_id", "membership_user_id")
    )
  end

  it "rejects duplicate restore and rolls back an invalid audit action" do
    expect {
      described_class.new(membership, actor: group_admin, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(membership.reload).to be_activity_suspended

    described_class.new(membership, actor: group_admin, public_reason: "Resolved").call!
    expect { described_class.new(membership, actor: group_admin, public_reason: "Again").call! }.to raise_error(described_class::InvalidState)
  end

  it "does not let a global admin restore group membership activity directly" do
    global_admin = User.create!(name: "Global actor", email: "restore-global-actor@example.com", password: "password123!", global_admin: true)

    expect {
      described_class.new(membership, actor: global_admin, public_reason: "Blocked").call!
    }.to raise_error(described_class::InvalidState)
    expect(membership.reload).to be_activity_suspended
  end

end
