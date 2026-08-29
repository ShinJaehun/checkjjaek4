require "rails_helper"

RSpec.describe Users::RestoreAccount do
  let(:actor) { User.create!(name: "Admin", email: "restore-service-admin@example.com", password: "password123!", global_admin: true) }
  let(:user) { User.create!(name: "Reader", email: "restore-service-reader@example.com", password: "password123!", suspended_at: Time.current) }
  let!(:suspension) do
    ModerationAction.create!(target: user, actor:, action_type: :suspend, public_reason: "Original reason", internal_note: "Original note")
  end

  it "restores the user with a separate audit action linked to the suspension" do
    original_attributes = suspension.attributes

    expect {
      described_class.new(user, actor:, public_reason: "Restriction lifted", internal_note: "Reviewed").call!
    }.to change(ModerationAction, :count).by(1)

    restore = ModerationAction.order(:id).last
    expect(user.reload).not_to be_suspended
    expect(restore).to be_action_type_restore
    expect(restore.reversal_of).to eq(suspension)
    expect(restore.public_reason).to eq("Restriction lifted")
    expect(restore.internal_note).to eq("Reviewed")
    expect(suspension.reload.attributes).to eq(original_attributes)
  end

  it "rejects active, withdrawn, and stale double restore attempts" do
    active_user = User.create!(name: "Active", email: "restore-service-active@example.com", password: "password123!")
    expect { described_class.new(active_user, actor:, public_reason: "No suspension").call! }.to raise_error(described_class::InvalidState)

    user.update_columns(withdrawn_at: Time.current)
    expect { described_class.new(user, actor:, public_reason: "Terminal").call! }.to raise_error(described_class::InvalidState)
    user.update_columns(withdrawn_at: nil)

    described_class.new(user, actor:, public_reason: "First restore").call!
    expect { described_class.new(user, actor:, public_reason: "Second restore").call! }.to raise_error(described_class::InvalidState)
  end

  it "keeps the user suspended when the restore audit action is invalid" do
    expect {
      described_class.new(user, actor:, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(user.reload).to be_suspended
    expect(ModerationAction.where(reversal_of: suspension)).to be_empty
  end
end
