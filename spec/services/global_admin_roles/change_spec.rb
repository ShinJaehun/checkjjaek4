require "rails_helper"

RSpec.describe GlobalAdminRoles::Change do
  let(:admin) { User.create!(name: "Existing admin", email: "role-service-admin@example.com", password: "password123!", global_admin: true) }
  let(:user) { User.create!(name: "Reader", email: "role-service-reader@example.com", password: "password123!") }

  def change_for(target, action:, reason: "Staffing change")
    described_class.new(
      user_id: target.id,
      action:,
      reason:,
      operator_uid: 1000,
      operator_account: "deploy",
      server_hostname: "app-server",
      execution_id: SecureRandom.uuid
    )
  end

  it "grants and revokes with one audit row for each actual transition" do
    admin

    expect { change_for(user, action: :grant).call! }.to change(GlobalAdminRoleChange, :count).by(1)
    grant = GlobalAdminRoleChange.find_by!(user: user, action: :grant)
    expect(user.reload).to be_global_admin
    expect(grant).to have_attributes(global_admin_before: false, global_admin_after: true, reason: "Staffing change")

    expect { change_for(user, action: :revoke).call! }.to change(GlobalAdminRoleChange, :count).by(1)
    revoke = GlobalAdminRoleChange.find_by!(user: user, action: :revoke)
    expect(user.reload).not_to be_global_admin
    expect(revoke).to have_attributes(global_admin_before: true, global_admin_after: false)
    expect(GlobalAdminRoleChange.where(user: user).count).to eq(2)
  end

  it "rejects withdrawn and suspended grant targets without an audit row" do
    [ :withdrawn_at, :suspended_at ].each do |status|
      user.update!(status => Time.current)
      expect { change_for(user, action: :grant).call! }.to raise_error(described_class::InvalidState)
      expect(user.reload).not_to be_global_admin
      expect(GlobalAdminRoleChange.where(user: user)).to be_empty
      user.update!(status => nil)
    end
  end

  it "rejects duplicate grants and revokes without another audit row" do
    admin
    change_for(user, action: :grant).call!
    expect { change_for(user, action: :grant).call! }.to raise_error(described_class::InvalidState)

    change_for(user, action: :revoke).call!
    expect { change_for(user, action: :revoke).call! }.to raise_error(described_class::InvalidState)
    expect(GlobalAdminRoleChange.where(user: user).count).to eq(2)
  end

  it "protects the last active admin even when suspended or withdrawn admins exist" do
    suspended = User.create!(name: "Suspended admin", email: "role-service-suspended@example.com", password: "password123!", global_admin: true, suspended_at: Time.current)
    withdrawn = User.create!(name: "Withdrawn admin", email: "role-service-withdrawn@example.com", password: "password123!", global_admin: true, withdrawn_at: Time.current)
    expect(suspended).to be_suspended
    expect(withdrawn).to be_withdrawn

    expect { change_for(admin, action: :revoke).call! }.to raise_error(described_class::LastActiveAdmin)
    expect(admin.reload).to be_global_admin
    expect(GlobalAdminRoleChange.where(user: admin)).to be_empty
  end

  it "rolls back the user role when audit persistence fails" do
    allow(GlobalAdminRoleChange).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(GlobalAdminRoleChange.new))

    expect { change_for(user, action: :grant).call! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(user.reload).not_to be_global_admin
    expect(GlobalAdminRoleChange.where(user: user)).to be_empty
  end
end
