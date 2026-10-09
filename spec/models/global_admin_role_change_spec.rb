require "rails_helper"

RSpec.describe GlobalAdminRoleChange, type: :model do
  let(:user) { User.create!(name: "Role target", email: "role-change-model@example.com", password: "password123!") }

  def change_for(action: :grant, before: false, after: true)
    described_class.new(
      user:,
      action:,
      global_admin_before: before,
      global_admin_after: after,
      reason: "Operational assignment",
      operator_uid: 1000,
      operator_account: "deploy",
      server_hostname: "app-server",
      execution_id: SecureRandom.uuid
    )
  end

  it "records the target, transition, reason, and server execution information" do
    record = change_for.tap(&:save!)

    expect(record).to have_attributes(
      user:,
      action: "grant",
      global_admin_before: false,
      global_admin_after: true,
      reason: "Operational assignment",
      operator_uid: 1000,
      operator_account: "deploy",
      server_hostname: "app-server"
    )
    expect(record.execution_id).to be_present
    expect(record.created_at).to be_present
  end

  it "rejects an invalid transition or missing reason" do
    expect(change_for(action: :revoke)).not_to be_valid
    expect(change_for(before: true, after: true)).not_to be_valid
    expect(change_for.tap { |record| record.reason = " " }).not_to be_valid
  end

  it "does not allow persisted audit rows to be changed or deleted" do
    record = change_for.tap(&:save!)

    expect { record.update!(reason: "Replacement") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { record.update_columns(reason: "Replacement") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { record.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { record.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(record.reload.reason).to eq("Operational assignment")
  end
end
