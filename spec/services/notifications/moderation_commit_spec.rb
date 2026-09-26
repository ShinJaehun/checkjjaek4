require "rails_helper"

RSpec.describe "Moderation notification commit delivery" do
  self.use_transactional_tests = false

  before do
    suffix = SecureRandom.hex(6)
    @actor = User.create!(name: "Admin", email: "commit-admin-#{suffix}@example.com", password: "password123!", global_admin: true)
    @recipient = User.create!(name: "Reader", email: "commit-reader-#{suffix}@example.com", password: "password123!")
  end

  after do
    Notification.where(recipient_id: @recipient.id).delete_all
    ModerationAction.where(target_type: "User", target_id: @recipient.id).delete_all
    @recipient.destroy!
    @actor.destroy!
  end

  it "delivers the exact audit row only after the outer transaction commits" do
    User.transaction do
      Users::SuspendAccount.new(@recipient, actor: @actor, public_reason: "other").call!
      expect(Notification.where(recipient: @recipient)).to be_empty
    end

    action = ModerationAction.find_by!(target: @recipient, action_type: :suspend)
    notification = Notification.find_by!(recipient: @recipient, notifiable: action)
    expect(notification).to have_attributes(actor: @actor, action: "user_account_suspended")
  end

  it "does not deliver when the outer transaction rolls back" do
    User.transaction do
      Users::SuspendAccount.new(@recipient, actor: @actor, public_reason: "other").call!
      raise ActiveRecord::Rollback
    end

    expect(@recipient.reload).not_to be_suspended
    expect(ModerationAction.where(target: @recipient)).to be_empty
    expect(Notification.where(recipient: @recipient)).to be_empty
  end

  it "keeps the moderation state and audit when notification persistence fails" do
    allow(Notification).to receive(:notify_once).and_raise(ActiveRecord::RecordInvalid.new(Notification.new))
    expect(Rails.logger).to receive(:error).with(/notification_action=user_account_suspended.*recipient_id=#{@recipient.id}/)

    expect(Users::SuspendAccount.new(@recipient, actor: @actor, public_reason: "other").call!).to eq(@recipient)

    expect(@recipient.reload).to be_suspended
    expect(ModerationAction.where(target: @recipient, action_type: :suspend).count).to eq(1)
    expect(Notification.where(recipient: @recipient)).to be_empty
  end
end
