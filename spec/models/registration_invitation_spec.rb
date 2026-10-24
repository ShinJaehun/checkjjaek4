require "rails_helper"

RSpec.describe RegistrationInvitation, type: :model do
  let!(:admin) { User.create!(name: "Admin", email: "model-invite-admin@example.com", password: "password123!", global_admin: true) }

  it "enforces one pending invitation per email in the database" do
    first = described_class.new(email: "pending@example.com", invited_by: admin)
    first.issue_token!
    first.save!

    second = described_class.new(email: first.email, invited_by: admin)
    second.issue_token!
    expect(second).not_to be_valid
    expect {
      described_class.insert_all!([ {
        email: first.email, token_digest: second.token_digest, expires_at: second.expires_at,
        invited_by_id: admin.id, created_at: Time.current, updated_at: Time.current
      } ])
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
