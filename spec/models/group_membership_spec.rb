require "rails_helper"

RSpec.describe GroupMembership, type: :model do
  let(:owner) { User.create!(name: "Owner", email: "membership-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:member) { User.create!(name: "Member", email: "membership-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:group) { Group.create!(owner: owner, name: "Readers", group_type: :approval_group) }

  it "does not allow duplicate memberships" do
    described_class.create!(group: group, user: member, status: :pending)
    duplicate = described_class.new(group: group, user: member, status: :active)

    expect(duplicate).not_to be_valid
  end

  it "requires the owner membership to be active" do
    membership = group.group_memberships.find_by!(user: owner)

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

  it "allows active and inactive membership transitions" do
    membership = described_class.create!(group: group, user: member, status: :active)

    expect(membership.update(status: :inactive)).to be(true)
    expect(membership.update(status: :active)).to be(true)
  end

  it "does not allow inactive membership to become pending or invited" do
    membership = described_class.create!(group: group, user: member, status: :active)
    membership.update!(status: :inactive)

    expect(membership.update(status: :pending)).to be(false)
    expect(membership.update(status: :invited)).to be(false)
  end

  it "does not allow the owner membership to become inactive" do
    membership = group.group_memberships.find_by!(user: owner)

    expect(membership.update(status: :inactive)).to be(false)
  end

  it "does not allow the owner membership to be destroyed" do
    membership = group.group_memberships.find_by!(user: owner)

    expect {
      membership.destroy
    }.not_to change(described_class, :count)

    expect(membership).not_to be_destroyed
  end
end
