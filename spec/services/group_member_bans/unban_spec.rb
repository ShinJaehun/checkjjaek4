require "rails_helper"

RSpec.describe GroupMemberBans::Unban do
  let(:group_admin) { User.create!(name: "Admin", email: "unban-service-admin@example.com", password: "password123!") }
  let(:member) { User.create!(name: "Member", email: "unban-service-member@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Bans", group_type: :public_group) }

  it "records a reversal, removes only the marker, and preserves both audits" do
    membership = group.group_memberships.create!(user: member, status: :active)
    ban = GroupMemberBans::Ban.new(membership, actor: group_admin, public_reason: "Ban").call!
    original = ban.current_ban_action

    described_class.new(ban, actor: group_admin, public_reason: "Unban", internal_note: "Reviewed").call!
    reversal = ModerationAction.find_by!(reversal_of: original)

    expect(GroupMemberBan.exists?(ban.id)).to be(false)
    expect(group.group_memberships.exists?(user: member)).to be(false)
    expect(original.reload).to be_persisted
    expect(reversal).to have_attributes(
      action_type: "unban_from_group",
      membership_group_id: group.id,
      membership_user_id: member.id,
      public_reason: "Unban",
      internal_note: "Reviewed"
    )
  end

  it "keeps the marker when the reversal audit is invalid" do
    membership = group.group_memberships.create!(user: member, status: :active)
    ban = GroupMemberBans::Ban.new(membership, actor: group_admin, public_reason: "Ban").call!

    expect {
      described_class.new(ban, actor: group_admin, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(ban.reload).to be_persisted
    expect(ModerationAction.where(target: ban, action_type: :unban_from_group)).to be_empty
  end

  it "rejects an actor who is not the group admin" do
    membership = group.group_memberships.create!(user: member, status: :active)
    ban = GroupMemberBans::Ban.new(membership, actor: group_admin, public_reason: "Ban").call!

    expect {
      described_class.new(ban, actor: member, public_reason: "Unban").call!
    }.to raise_error(GroupMemberBans::Unban::InvalidState)
    expect(ban.reload).to be_persisted
  end

  it "does not lift a ban after the group is inactive" do
    membership = group.group_memberships.create!(user: member, status: :active)
    ban = GroupMemberBans::Ban.new(
      membership,
      actor: group_admin,
      public_reason: "Ban"
    ).call!

    group.update!(
      lifecycle_status: :inactive,
      closure_reason: "Group closed"
    )
    expect {
      described_class.new(
        ban,
        actor: group_admin,
        public_reason: "Unban"
      ).call!
    }.to raise_error(described_class::InvalidState)

    expect(ban.reload).to be_persisted
  end
end
