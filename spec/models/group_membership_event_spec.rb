require "rails_helper"

RSpec.describe GroupMembershipEvent, type: :model do
  let(:group_admin) do
    User.create!(name: "Group admin", email: "membership-event-admin@example.com", password: "password123!", password_confirmation: "password123!")
  end

  it "defines the supported event types and orders recent events newest first" do
    expect(described_class.event_types).to eq(
      "joined" => 0,
      "requested_to_join" => 1,
      "join_request_cancelled" => 2,
      "approved" => 3,
      "request_rejected" => 4,
      "invited" => 5,
      "invitation_accepted" => 6,
      "invitation_declined" => 7,
      "invitation_revoked" => 8,
      "left" => 9,
      "removed" => 10,
      "admin_role_revoked" => 11,
      "admin_role_granted" => 12
    )

    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Ordered", group_type: :public_group)
    older = group.group_membership_events.first
    newer = group.group_membership_events.create!(user: group_admin, actor: group_admin, event_type: :left)

    expect(group.group_membership_events.recent).to eq([ newer, older ])
  end

  it "records the initial group admin membership as joined by the group admin" do
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Created", group_type: :public_group)

    expect(group.group_membership_events.sole).to have_attributes(
      event_type: "joined",
      user: group_admin,
      actor: group_admin
    )
  end

  it "does not allow persisted history rows to be updated or destroyed" do
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Append only", group_type: :public_group)
    event = group.group_membership_events.sole

    expect { event.update!(event_type: :left) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.update_columns(event_type: described_class.event_types[:left]) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.touch }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
