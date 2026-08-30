require "rails_helper"

RSpec.describe GroupMemberBanPolicy do
  it "allows only the group admin to lift a current ban" do
    group_admin = User.create!(name: "Admin", email: "ban-policy-admin@example.com", password: "password123!")
    member = User.create!(name: "Member", email: "ban-policy-member@example.com", password: "password123!")
    global_admin = User.create!(name: "Global", email: "ban-policy-global@example.com", password: "password123!", global_admin: true)
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Bans", group_type: :public_group)
    ban = GroupMemberBan.create!(group:, user: member)

    expect(described_class.new(group_admin, ban).destroy?).to be(true)
    expect(described_class.new(global_admin, ban).destroy?).to be(false)
    expect(described_class.new(member, ban).destroy?).to be(false)
  end
end
