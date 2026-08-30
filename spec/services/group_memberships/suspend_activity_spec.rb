require "rails_helper"

RSpec.describe GroupMemberships::SuspendActivity do
  let(:group_admin) { User.create!(name: "Admin", email: "activity-suspend-admin@example.com", password: "password123!") }
  let(:member) { User.create!(name: "Member", email: "activity-suspend-member@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :private_group) }
  let(:membership) { group.group_memberships.create!(user: member, status: :active) }

  it "suspends only group activity and records an audit action atomically" do
    described_class.new(membership, actor: group_admin, public_reason: "Group rule", internal_note: "Case 1").call!

    action = membership.current_activity_suspension_action
    expect(membership.reload).to be_activity_suspended
    expect(membership).to be_active
    expect(member.reload).not_to be_suspended
    expect(action).to have_attributes(
      target: membership,
      actor: group_admin,
      action_type: "suspend_activity",
      public_reason: "Group rule",
      internal_note: "Case 1",
      membership_group_id: group.id,
      membership_user_id: member.id
    )
  end

  it "rejects duplicate and group-admin membership suspension" do
    described_class.new(membership, actor: group_admin, public_reason: "First").call!
    expect { described_class.new(membership, actor: group_admin, public_reason: "Again").call! }.to raise_error(described_class::InvalidState)

    admin_membership = group.group_memberships.find_by!(user: group_admin)
    expect { described_class.new(admin_membership, actor: group_admin, public_reason: "Blocked").call! }.to raise_error(described_class::InvalidState)
  end

  it "rolls back state when the audit action is invalid" do
    expect {
      described_class.new(membership, actor: group_admin, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(membership.reload).to be_moderation_status_normal
    expect(ModerationAction.where(target: membership)).to be_empty
  end

  it "does not change membership moderation when the user account is suspended" do
    global_admin = User.create!(name: "Global", email: "activity-global@example.com", password: "password123!", global_admin: true)

    Users::SuspendAccount.new(member, actor: global_admin, public_reason: "Account reason").call!

    expect(membership.reload).to be_moderation_status_normal
  end
end
