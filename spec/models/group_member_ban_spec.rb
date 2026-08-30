require "rails_helper"

RSpec.describe GroupMemberBan, type: :model do
  let(:group_admin) { User.create!(name: "Admin", email: "ban-model-admin@example.com", password: "password123!") }
  let(:member) { User.create!(name: "Member", email: "ban-model-member@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Bans", group_type: :public_group) }

  it "allows only one current ban per group and user" do
    described_class.create!(group:, user: member)
    duplicate = described_class.new(group:, user: member)

    expect(duplicate).not_to be_valid
  end

  it "does not allow the group admin to be banned" do
    expect(described_class.new(group:, user: group_admin)).not_to be_valid
  end
end
