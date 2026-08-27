require "rails_helper"

RSpec.describe GroupLifecycleEvent, type: :model do
  it "defines the supported lifecycle event types and limits detail length" do
    expect(described_class.event_types).to eq(
      "opening_requested" => 0,
      "opening_approved" => 1,
      "operations_closed" => 2,
      "reactivation_requested" => 3,
      "reactivation_approved" => 4
    )

    event = described_class.new(detail: "a" * 501)
    expect(event).not_to be_valid
    expect(event.errors[:detail]).to be_present
  end

  it "allows only the pending opening snapshot exception to append-only updates" do
    group_admin = User.create!(name: "Group admin", email: "event-group_admin@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(group_admin: group_admin, name: "Pending", group_type: :public_group, application_purpose: "Initial")
    opening = group.lifecycle_events.create!(actor: group_admin, event_type: :opening_requested, detail: "Initial")
    closure = group.lifecycle_events.create!(actor: group_admin, event_type: :operations_closed, detail: "Old reason")

    expect(opening.update(detail: "Updated")).to be(true)
    expect(closure.update(detail: "Replacement")).to be(false)
    expect(closure.reload.detail).to eq("Old reason")
  end
end
