require "rails_helper"
require "timeout"

RSpec.describe "Group reactivation during account withdrawal", type: :request do
  self.use_transactional_tests = false

  let(:password) { "password123!" }
  let!(:owner) { User.create!(name: "Owner", email: "reactivation-race-owner@example.com", password:) }
  let!(:reviewer) { User.create!(name: "Reviewer", email: "reactivation-race-reviewer@example.com", password:, global_admin: true) }
  let!(:group) do
    Group.create!(group_admin: owner, name: "Closed club", lifecycle_status: :active).tap do |record|
      record.update!(lifecycle_status: :inactive, closed_at: Time.current, closure_reason: "Closed")
    end
  end

  after do
    reviewer.received_notifications.delete_all
    group.reload.destroy!
    owner.reload.destroy!
    reviewer.destroy!
  end

  it "denies an already authenticated request when withdrawal commits before the reactivation lock" do
    authorized = Queue.new
    resume_request = Queue.new
    reactivation_path = group_reactivation_requests_path(group)
    reactivation_session = signed_in_session
    withdrawal_session = signed_in_session
    allow_any_instance_of(Groups::ReactivationRequestsController).to receive(:create).and_wrap_original do |action|
      # The request has passed authentication and the initial Group policy check.
      authorized << true
      resume_request.pop
      action.call
    end

    reactivation = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        reactivation_session.post reactivation_path
        reactivation_session.response
      end
    end

    Timeout.timeout(15) { authorized.pop }
    withdrawal_session.delete account_withdrawal_path, params: { account_withdrawal: { current_password: password } }
    expect(withdrawal_session.response).to have_http_status(:see_other)
    expect(owner.reload).to be_withdrawn

    resume_request << true
    result = Timeout.timeout(15) { reactivation.value }
    expect(result.status).to eq(302)
    expect(URI.parse(result.location).path).to eq(root_path)
    expect(group.reload).to be_inactive
    expect(group.group_admin_id).to eq(owner.id)
    expect(group.group_memberships.where(user: owner)).to be_empty
    expect(group.lifecycle_events.reactivation_requested).to be_empty
    expect(reviewer.received_notifications.where(action: :group_reactivation_requested)).to be_empty
  ensure
    reactivation&.kill if reactivation&.alive?
    reactivation&.join
  end

  def signed_in_session
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post user_session_path, params: { user: { email: owner.email, password: } }
    expect(session.response).to have_http_status(:found)
    session
  end
end
