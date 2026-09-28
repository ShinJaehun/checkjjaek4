require "rails_helper"

RSpec.describe GroupMemberBanPolicy do
  it "allows only the group admin to lift a current ban" do
    group_admin = User.create!(name: "Admin", email: "ban-policy-admin@example.com", password: "password123!")
    member = User.create!(name: "Member", email: "ban-policy-member@example.com", password: "password123!")
    global_admin = User.create!(name: "Global", email: "ban-policy-global@example.com", password: "password123!", global_admin: true)
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Bans", group_type: :public_group)
    ban = GroupMemberBan.create!(group:, user: member)

    expect(described_class.new(group_admin, ban).unban?).to be(true)
    expect(described_class.new(global_admin, ban).unban?).to be(false)
    expect(described_class.new(member, ban).unban?).to be(false)

    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    expect(described_class.new(group_admin, ban).unban?).to be(true)

    group.update!(operation_suspended_at: Time.current)
    expect(described_class.new(group_admin, ban).unban?).to be(false)
  end

  it "allows a global admin only when that user is the group admin" do
    group_admin = User.create!(name: "Both roles", email: "ban-policy-both@example.com", password: "password123!", global_admin: true)
    member = User.create!(name: "Member", email: "ban-policy-both-member@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Managed bans", group_type: :public_group)
    ban = GroupMemberBan.create!(group:, user: member)

    expect(described_class.new(group_admin, ban).unban?).to be(true)
  end
end
