require "rails_helper"

RSpec.describe GroupMembership, type: :model do
  let(:group_admin) { User.create!(name: "Group admin", email: "membership-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:member) { User.create!(name: "Member", email: "membership-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Readers", group_type: :approval_group) }

  it "uses only pre-membership and active lifecycle states" do
    expect(described_class.statuses.keys).to contain_exactly("pending", "active", "invited")
  end

  it "does not allow duplicate memberships" do
    described_class.create!(group: group, user: member, status: :pending)
    duplicate = described_class.new(group: group, user: member, status: :active)

    expect(duplicate).not_to be_valid
  end

  it "requires the group_admin membership to be active" do
    membership = group.group_memberships.find_by!(user: group_admin)

    expect(membership.update(status: :pending)).to be(false)
  end

  it "does not allow an active membership to return to pending" do
    membership = described_class.create!(group: group, user: member, status: :active)

    expect(membership.update(status: :pending)).to be(false)
  end

  it "supports an invitation becoming active" do
    membership = described_class.create!(group: group, user: member, status: :invited)

    expect(membership).to be_invited
    expect(membership.update(status: :active)).to be(true)
  end

  it "does not allow an invitation to become pending" do
    membership = described_class.create!(group: group, user: member, status: :invited)

    expect(membership.update(status: :pending)).to be(false)
  end

  it "keeps activity moderation separate from membership lifecycle" do
    membership = described_class.create!(group: group, user: member, status: :active)

    expect(membership).to be_moderation_status_normal
    membership.update!(moderation_status: :activity_suspended)
    expect(membership).to be_active

    expect(membership).to be_activity_suspended
  end

  it "does not allow the group_admin membership to be destroyed" do
    membership = group.group_memberships.find_by!(user: group_admin)

    expect {
      membership.destroy
    }.not_to change(described_class, :count)

    expect(membership).not_to be_destroyed
  end

  it "allows an inactive group's historical admin membership to be destroyed" do
    membership = group.group_memberships.find_by!(user: group_admin)
    group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)

    expect {
      membership.destroy!
    }.to change(described_class, :count).by(-1)
    expect(group.reload.group_admin).to eq(group_admin)
  end
end
