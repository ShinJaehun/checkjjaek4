require "rails_helper"

RSpec.describe Notifications::GroupMembershipNotifier do
  let(:actor) { User.create!(name: "Applicant", email: "membership-notifier-actor@example.com", password: "password123!") }
  let(:recipient) { User.create!(name: "Admin", email: "membership-notifier-recipient@example.com", password: "password123!") }
  let(:group) { Group.create!(name: "Approval club", group_admin: recipient, lifecycle_status: :active, group_type: :approval_group) }

  before do
    @commit_callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| @commit_callbacks << callback }
  end

  def deliver(event, recipient_ids: [ recipient.id ])
    described_class.schedule(event:, recipient_ids:)
    @commit_callbacks.shift&.call
  end

  it "maps only the three approved workflow events to their actual event rows" do
    {
      requested_to_join: "group_membership_requested_to_join",
      approved: "group_membership_approved",
      request_rejected: "group_membership_request_rejected"
    }.each do |event_type, notification_action|
      event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type:)
      deliver(event)

      expect(Notification.find_by!(recipient:, notifiable: event)).to have_attributes(
        action: notification_action, actor:
      )
    end
  end

  it "excludes the actor and deduplicates recipients and repeated delivery" do
    event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type: :requested_to_join)
    deliver(event, recipient_ids: [ actor.id, recipient.id, recipient.id ])
    deliver(event)

    expect(Notification.where(notifiable: event).pluck(:recipient_id)).to eq([ recipient.id ])
    described_class.schedule(event:, recipient_ids: [ actor.id ])
    expect(@commit_callbacks).to be_empty
  end

  it "continues after a recipient failure without logging its message" do
    second = User.create!(name: "Second", email: "membership-notifier-second@example.com", password: "password123!")
    event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type: :requested_to_join)
    allow(Notification).to receive(:notify_once).and_wrap_original do |method, **attributes|
      raise StandardError, "PRIVATE_ERROR" if attributes.fetch(:recipient) == recipient

      method.call(**attributes)
    end
    expect(Rails.logger).to receive(:error) do |message|
      expect(message).to include("event_type=requested_to_join", "event_id=#{event.id}", "recipient_id=#{recipient.id}", "StandardError")
      expect(message).not_to include("PRIVATE_ERROR")
    end

    deliver(event, recipient_ids: [ recipient.id, second.id ])
    expect(Notification.where(notifiable: event).pluck(:recipient_id)).to eq([ second.id ])
  end

  it "treats a uniqueness race as delivered only when the exact notification already exists" do
    event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type: :requested_to_join)
    Notification.create!(recipient:, actor:, action: :group_membership_requested_to_join, notifiable: event)
    allow(Notification).to receive(:notify_once).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))
    expect(Rails.logger).not_to receive(:error)

    deliver(event)
    expect(Notification.where(notifiable: event).count).to eq(1)
  end
end
