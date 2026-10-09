require "rails_helper"

RSpec.describe "Concurrent global admin revocation" do
  self.use_transactional_tests = false

  before do
    suffix = SecureRandom.hex(6)
    @admins = [
      User.create!(name: "First admin", email: "first-role-admin-#{suffix}@example.com", password: "password123!", global_admin: true),
      User.create!(name: "Second admin", email: "second-role-admin-#{suffix}@example.com", password: "password123!", global_admin: true)
    ]
  end

  after do
    GlobalAdminRoleChange.where(user_id: @admins.map(&:id)).delete_all
    @admins.each(&:destroy!)
  end

  it "leaves one active admin and one audit row after simultaneous revocations" do
    ready = Queue.new
    start = Queue.new

    attempts = @admins.map do |admin|
      Thread.new(admin.id) do |user_id|
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            GlobalAdminRoles::Change.new(
              user_id:,
              action: :revoke,
              reason: "Staffing change",
              operator_uid: 1000,
              operator_account: "deploy",
              server_hostname: "app-server",
              execution_id: SecureRandom.uuid
            ).call!
            :revoked
          rescue StandardError => error
            error
          end
        end
      end
    end

    @admins.size.times { ready.pop }
    @admins.size.times { start << true }
    results = attempts.map(&:value)

    expect(results.count(:revoked)).to eq(1)
    expect(results.count { |result| result.is_a?(GlobalAdminRoles::Change::LastActiveAdmin) }).to eq(1)
    expect(User.where(id: @admins.map(&:id), global_admin: true, suspended_at: nil, withdrawn_at: nil).count).to eq(1)
    expect(GlobalAdminRoleChange.where(user_id: @admins.map(&:id)).count).to eq(1)
  end
end
