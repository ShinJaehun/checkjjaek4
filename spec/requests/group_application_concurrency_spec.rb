require "rails_helper"
require "timeout"

RSpec.describe "Concurrent group opening applications", type: :request do
  # Each request needs its own connection and must see the other request's commit.
  self.use_transactional_tests = false

  before do
    @owner = User.create!(name: "Concurrent applicant", email: "opening-race-#{SecureRandom.hex(6)}@example.com", password: "password123!")
  end

  after do
    @owner.administered_groups.each do |group|
      Notification.where(notifiable_type: "GroupLifecycleEvent", notifiable_id: group.lifecycle_events.select(:id)).delete_all
      group.destroy!
    end
    @owner.reload.destroy!
  end

  it "allows exactly one pending initial application from two simultaneous POSTs" do
    # Load these constants before starting requests on separate threads.
    GroupsController
    GroupLifecycleEvent
    Notifications::GroupLifecycleNotifier
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.post user_session_path, params: { user: { email: @owner.email, password: "password123!" } }
          raise "Login failed" unless session.response.redirect?

          ready << true
          start.pop
          session.post groups_path, params: { group: {
            name: "Concurrent club #{index}", group_type: "public_group", application_purpose: "Read together"
          } }
          session.response.status
        end
      end
    end

    begin
      Timeout.timeout(15) { 2.times { ready.pop } }
      2.times { start << true }
      statuses = Timeout.timeout(15) { threads.map(&:value) }
      expect(statuses.sort).to eq([ 302, 422 ])
      expect(@owner.administered_groups.pending_opening_applications.count).to eq(1)
      group = @owner.administered_groups.sole
      expect(group.lifecycle_events.opening_requested.count).to eq(1)
      expect(group.group_memberships.where(user: @owner).count).to eq(1)
    ensure
      threads.each do |thread|
        thread.kill if thread.alive?
        thread.join
      end
    end
  end
end
