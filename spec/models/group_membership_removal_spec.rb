require "rails_helper"

RSpec.describe GroupMembershipRemoval, type: :model do
  it "keeps one removal marker per user and group" do
    group_admin = User.create!(name: "Group admin", email: "removal-model-admin@example.com", password: "password123!")
    member = User.create!(name: "Member", email: "removal-model-member@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Removal marker", group_type: :private_group)
    described_class.create!(group:, user: member, removed_by: group_admin)

    duplicate = described_class.new(group:, user: member, removed_by: group_admin)

    expect(duplicate).not_to be_valid
  end
end
