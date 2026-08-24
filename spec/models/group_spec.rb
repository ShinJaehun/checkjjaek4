require "rails_helper"

RSpec.describe Group, type: :model do
  let(:owner) { User.create!(name: "Owner", email: "group-owner@example.com", password: "password123!", password_confirmation: "password123!") }

  it "requires a name" do
    group = described_class.new(owner: owner, name: "", group_type: :public_group)

    expect(group).not_to be_valid
  end

  it "creates an active membership for its owner" do
    group = described_class.create!(owner: owner, name: "Readers", group_type: :public_group)

    expect(group.group_memberships.find_by(user: owner)).to be_active
  end

  it "includes only active memberships in members" do
    pending_user = User.create!(name: "Pending", email: "pending-group-member@example.com", password: "password123!", password_confirmation: "password123!")
    active_user = User.create!(name: "Active", email: "active-group-member@example.com", password: "password123!", password_confirmation: "password123!")
    group = described_class.create!(owner: owner, name: "Readers", group_type: :approval_group)
    group.group_memberships.create!(user: pending_user, status: :pending)
    group.group_memberships.create!(user: active_user, status: :active)

    expect(group.members).to include(owner, active_user)
    expect(group.members).not_to include(pending_user)
  end

  it "includes only active memberships in a user's joined groups" do
    user = User.create!(name: "Reader", email: "joined-groups-reader@example.com", password: "password123!", password_confirmation: "password123!")
    pending_group = described_class.create!(owner: owner, name: "Pending", group_type: :approval_group)
    active_group = described_class.create!(owner: owner, name: "Active", group_type: :public_group)
    pending_group.group_memberships.create!(user: user, status: :pending)
    active_group.group_memberships.create!(user: user, status: :active)

    expect(user.joined_groups).to include(active_group)
    expect(user.joined_groups).not_to include(pending_group)
  end
end
