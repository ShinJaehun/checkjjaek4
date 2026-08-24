require "rails_helper"

RSpec.describe GroupMembershipPolicy do
  let(:owner) { User.create!(name: "Owner", email: "membership-policy-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:member) { User.create!(name: "Member", email: "membership-policy-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "membership-policy-other@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:group) { Group.create!(owner: owner, name: "Approval", group_type: :approval_group) }

  it "allows only the group owner to approve a pending membership" do
    membership = group.group_memberships.create!(user: member, status: :pending)

    expect(described_class.new(owner, membership).approve?).to be(true)
    expect(described_class.new(other_user, membership).approve?).to be(false)
  end

  it "does not allow an active membership to be approved again" do
    membership = group.group_memberships.create!(user: member, status: :active)

    expect(described_class.new(owner, membership).approve?).to be(false)
  end

  it "allows users to destroy only their own non-owner membership" do
    membership = group.group_memberships.create!(user: member, status: :pending)
    owner_membership = group.group_memberships.find_by!(user: owner)

    expect(described_class.new(member, membership).destroy?).to be(true)
    expect(described_class.new(other_user, membership).destroy?).to be(false)
    expect(described_class.new(owner, owner_membership).destroy?).to be(false)
  end
end
