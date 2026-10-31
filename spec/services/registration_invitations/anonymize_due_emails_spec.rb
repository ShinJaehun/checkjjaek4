require "rails_helper"

RSpec.describe RegistrationInvitations::AnonymizeDueEmails do
  include ActiveSupport::Testing::TimeHelpers

  let!(:admin) { User.create!(name: "Invitation admin", email: "retention-admin@example.com", password: "password123!", global_admin: true) }

  def invitation(email:, expires_at: 7.days.from_now, canceled_at: nil)
    record = RegistrationInvitation.new(email: email, invited_by: admin, canceled_at: canceled_at)
    record.issue_token!
    record.expires_at = expires_at
    record.created_at = expires_at - RegistrationInvitation::VALIDITY_PERIOD
    record.save!
    record
  end

  it "anonymizes expired emails after 30 days, keeps newer ones, and does not reprocess records" do
    travel_to Time.utc(2026, 11, 1, 12) do
      due = invitation(email: "expired-due@example.com", expires_at: 30.days.ago)
      recent = invitation(email: "expired-recent@example.com", expires_at: 30.days.ago + 1.second)
      original_expiry = due.expires_at
      original_digest = due.token_digest

      described_class.new.call

      expect(due.reload.email).to eq(due.anonymized_email)
      expect(due.expires_at).to eq(original_expiry)
      expect(due.token_digest).to eq(original_digest)
      expect(due.status).to eq(:expired)
      expect(recent.reload.email).to eq("expired-recent@example.com")
      expect { due.resend_token! }.to raise_error(ActiveRecord::RecordInvalid)
      expect { due.cancel! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(due).not_to be_active
      expect(RegistrationInvitationPolicy.new(admin, due).resend?).to be(false)

      updated_at = due.updated_at
      described_class.new.call
      expect(due.reload.updated_at).to eq(updated_at)

      replacement = invitation(email: "expired-due@example.com")
      expect(replacement).to be_active
    end
  end

  it "uses the cancellation date and leaves used and valid invitations untouched" do
    travel_to Time.utc(2026, 11, 1, 12) do
      due = invitation(email: "canceled-due@example.com", canceled_at: 30.days.ago,
                       expires_at: 29.days.ago)
      recent = invitation(email: "canceled-recent@example.com", canceled_at: 30.days.ago + 1.second,
                          expires_at: 60.days.ago)
      used = invitation(email: "used@example.com", expires_at: 60.days.ago)
      member = User.create!(name: "Member", email: used.email, password: "password123!", created_at: 61.days.ago)
      used.update!(consumed_at: 61.days.ago, user: member)
      active = invitation(email: "active@example.com")
      original_cancellation = due.canceled_at

      described_class.new.call

      expect(due.reload.email).to eq(due.anonymized_email)
      expect(due.canceled_at).to eq(original_cancellation)
      expect(due.status).to eq(:canceled)
      expect(recent.reload.email).to eq("canceled-recent@example.com")
      expect(used.reload).to have_attributes(email: "used@example.com", user_id: member.id)
      expect(active.reload.email).to eq("active@example.com")
    end
  end

  it "rechecks eligibility after locking when an expired invitation was resent" do
    travel_to Time.utc(2026, 11, 1, 12) do
      record = invitation(email: "resent@example.com", expires_at: 31.days.ago)
      stale_record = RegistrationInvitation.find(record.id)
      record.resend_token!

      described_class.new.send(:anonymize_if_due, stale_record, 30.days.ago)

      expect(record.reload.email).to eq("resent@example.com")
      expect(record).to be_active
    end
  end
end
