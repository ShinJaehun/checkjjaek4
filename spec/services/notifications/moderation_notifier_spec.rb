require "rails_helper"

RSpec.describe Notifications::ModerationNotifier do
  let(:actor) { User.create!(name: "Platform admin", email: "moderation-notifier-admin@example.com", password: "password123!", global_admin: true) }
  let(:recipient) { User.create!(name: "Recipient", email: "moderation-notifier-recipient@example.com", password: "password123!") }

  before do
    @commit_callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) do |&callback|
      @commit_callbacks << callback
    end
  end

  def deliver_after_commit(action, recipient_ids: [ recipient.id ])
    described_class.schedule(moderation_action: action, recipient_ids:)
    @commit_callbacks.shift.call
  end

  it "maps all eight audit events to notifications referencing their exact audit rows" do
    group = Group.create!(lifecycle_status: :active, group_admin: recipient, name: "Notifier group", group_type: :public_group)
    jjaek = recipient.jjaeks.create!(content: "Notifier Jjaek")
    comment = jjaek.comments.create!(user: recipient, content: "Notifier comment")

    user_suspend = ModerationAction.create!(target: recipient, actor:, action_type: :suspend, public_reason: "other")
    user_restore = ModerationAction.create!(target: recipient, actor:, action_type: :restore, public_reason: "Resolved", reversal_of: user_suspend)
    group_suspend = ModerationAction.create!(target: group, actor:, action_type: :suspend_group_operation, public_reason: "other")
    group_restore = ModerationAction.create!(target: group, actor:, action_type: :restore_group_operation, public_reason: "Resolved", reversal_of: group_suspend)
    jjaek_hide = ModerationAction.create!(target: jjaek, actor:, action_type: :hide, public_reason: "other", moderation_authority: "platform")
    jjaek_restore = ModerationAction.create!(target: jjaek, actor:, action_type: :restore, public_reason: "Resolved", moderation_authority: "platform", reversal_of: jjaek_hide)
    comment_hide = ModerationAction.create!(target: comment, actor:, action_type: :hide, public_reason: "other", moderation_authority: "platform")
    comment_restore = ModerationAction.create!(target: comment, actor:, action_type: :restore, public_reason: "Resolved", moderation_authority: "platform", reversal_of: comment_hide)

    {
      user_suspend => "user_account_suspended",
      user_restore => "user_account_restored",
      group_suspend => "group_operation_suspended",
      group_restore => "group_operation_restored",
      jjaek_hide => "jjaek_hidden",
      jjaek_restore => "jjaek_restored",
      comment_hide => "comment_hidden",
      comment_restore => "comment_restored"
    }.each do |action, notification_action|
      deliver_after_commit(action)
      notification = Notification.find_by!(notifiable: action, recipient:)
      expect(notification).to have_attributes(action: notification_action, actor:)
    end
  end

  it "maps membership activity suspension and restoration to their exact audit rows" do
    group = Group.create!(lifecycle_status: :active, group_admin: actor, name: "Membership group", group_type: :private_group)
    membership = group.group_memberships.create!(user: recipient, status: :active)
    suspension = ModerationAction.create!(target: membership, actor:, action_type: :suspend_activity, public_reason: "Group rule")
    restoration = ModerationAction.create!(target: membership, actor:, action_type: :restore_activity,
                                           public_reason: "Resolved", reversal_of: suspension)

    { suspension => "group_member_activity_suspended", restoration => "group_member_activity_restored" }.each do |action, notification_action|
      deliver_after_commit(action)
      notification = Notification.find_by!(notifiable: action, recipient:)
      expect(notification).to have_attributes(action: notification_action, actor:)
    end
  end

  it "does not schedule a membership activity notification for its actor" do
    group = Group.create!(lifecycle_status: :active, group_admin: actor, name: "Own group", group_type: :private_group)
    membership = group.group_memberships.find_by!(user: actor)
    action = ModerationAction.create!(target: membership, actor:, action_type: :suspend_activity, public_reason: "Group rule")

    described_class.schedule(moderation_action: action, recipient_ids: [ actor.id ])

    expect(@commit_callbacks).to be_empty
    expect(Notification.where(notifiable: action)).to be_empty
  end

  it "does not create a self notification and deduplicates repeated delivery" do
    action = ModerationAction.create!(target: recipient, actor:, action_type: :suspend, public_reason: "other")

    deliver_after_commit(action, recipient_ids: [ actor.id, recipient.id, recipient.id ])
    deliver_after_commit(action)

    expect(Notification.where(notifiable: action).pluck(:recipient_id)).to eq([ recipient.id ])
  end

  it "logs one recipient failure and continues delivering to the next recipient" do
    second_recipient = User.create!(name: "Second", email: "moderation-notifier-second@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin: recipient, name: "Fan-out group", group_type: :public_group)
    action = ModerationAction.create!(target: group, actor:, action_type: :suspend_group_operation, public_reason: "other")
    allow(Notification).to receive(:notify_once).and_wrap_original do |method, **attributes|
      raise ActiveRecord::RecordInvalid.new(Notification.new) if attributes.fetch(:recipient) == recipient

      method.call(**attributes)
    end
    expect(Rails.logger).to receive(:error).with(/moderation_action_id=#{action.id}.*recipient_id=#{recipient.id}.*ActiveRecord::RecordInvalid/)

    deliver_after_commit(action, recipient_ids: [ recipient.id, second_recipient.id ])

    expect(Notification.where(notifiable: action).pluck(:recipient_id)).to eq([ second_recipient.id ])
  end

  it "treats a unique-index race as delivered when the exact notification already exists" do
    action = ModerationAction.create!(target: recipient, actor:, action_type: :suspend, public_reason: "other")
    Notification.create!(recipient:, actor:, action: :user_account_suspended, notifiable: action)
    allow(Notification).to receive(:notify_once).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))
    expect(Rails.logger).not_to receive(:error)

    deliver_after_commit(action)

    expect(Notification.where(notifiable: action, recipient:).count).to eq(1)
  end

  it "does not write the audit internal note into a failure log" do
    action = ModerationAction.create!(target: recipient, actor:, action_type: :suspend,
                                      public_reason: "other", internal_note: "PRIVATE_CASE_NOTE")
    allow(Notification).to receive(:notify_once).and_raise(StandardError, "delivery failed PRIVATE_CASE_NOTE")
    expect(Rails.logger).to receive(:error) do |message|
      expect(message).to include("moderation_action_id=#{action.id}")
      expect(message).to include("recipient_id=#{recipient.id}")
      expect(message).to include("StandardError")
      expect(message).not_to include("PRIVATE_CASE_NOTE")
    end
    deliver_after_commit(action)
  end
end
