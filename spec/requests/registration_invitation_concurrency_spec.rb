require "rails_helper"
require "timeout"

RSpec.describe "Concurrent invitation sign-up", type: :request do
  self.use_transactional_tests = false

  it "allows only one request to consume a token" do
    suffix = SecureRandom.hex(6)
    admin = User.create!(name: "Concurrency Admin", email: "concurrent-invite-admin-#{suffix}@example.com", password: "password123!", global_admin: true)
    invitation = RegistrationInvitation.new(email: "concurrent-invitee-#{suffix}@example.com", invited_by: admin)
    token = invitation.issue_token!
    invitation.save!

    Users::RegistrationsController
    ready = Queue.new
    start = Queue.new
    results = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          session = ActionDispatch::Integration::Session.new(Rails.application)
          ready << true
          start.pop
          session.post(user_registration_path, params: {
            invitation_token: token,
            user: {
              name: "Concurrent Reader", handle: "concurrent_reader_#{suffix}", email: "wrong@example.com",
              password: "password123!", password_confirmation: "password123!", terms_accepted: "1"
            }
          })
          session.response.status
        end
      end
    end
    Timeout.timeout(15) { 2.times { ready.pop } }
    2.times { start << true }

    expect(Timeout.timeout(15) { results.map(&:value) }.sort).to eq([ 302, 403 ])
    expect(User.where(email: invitation.email).count).to eq(1)
    expect(invitation.reload.user).to eq(User.find_by!(email: invitation.email))
  ensure
    results&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
    invitee = User.find_by(email: invitation.email) if invitation
    invitation&.destroy!
    invitee&.destroy!
    admin&.destroy!
  end
end
