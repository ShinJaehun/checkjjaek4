require "rails_helper"

RSpec.describe Notifications::GroupLifecycleNotifier do
  let(:actor) { User.create!(name: "Actor", email: "lifecycle-notifier-actor@example.com", password: "password123!", global_admin: true) }
  let(:recipient) { User.create!(name: "Recipient", email: "lifecycle-notifier-recipient@example.com", password: "password123!") }
  let(:group) { Group.create!(name: "Reading club", group_admin: recipient, lifecycle_status: :active, group_type: :public_group) }

  before do
    @commit_callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| @commit_callbacks << callback }
  end

  def deliver(event, recipient_ids: [ recipient.id ])
    described_class.schedule(event:, recipient_ids:)
    @commit_callbacks.shift&.call
  end

  it "maps all seven events to their own audit rows" do
    lifecycle_actions = {
      opening_requested: :group_opening_requested,
      opening_approved: :group_opening_approved,
      operations_closed: :group_operations_closed,
      reactivation_requested: :group_reactivation_requested,
      reactivation_approved: :group_reactivation_approved
    }
    lifecycle_actions.each do |event_type, notification_action|
      event = GroupLifecycleEvent.create!(group:, actor:, event_type:)
      deliver(event)
      expect(Notification.find_by!(recipient:, notifiable: event)).to have_attributes(actor:, action: notification_action.to_s)
    end

    { admin_role_revoked: :group_admin_role_revoked, admin_role_granted: :group_admin_role_granted }.each do |event_type, notification_action|
      event = GroupMembershipEvent.create!(group:, user: recipient, actor:, event_type:)
      deliver(event)
      expect(Notification.find_by!(recipient:, notifiable: event)).to have_attributes(actor:, action: notification_action.to_s)
    end
  end

  it "excludes the actor and deduplicates recipients and repeat delivery" do
    event = GroupLifecycleEvent.create!(group:, actor:, event_type: :opening_requested)
    deliver(event, recipient_ids: [ actor.id, recipient.id, recipient.id ])
    deliver(event)

    expect(Notification.where(notifiable: event).pluck(:recipient_id)).to eq([ recipient.id ])
    described_class.schedule(event:, recipient_ids: [ actor.id ])
    expect(@commit_callbacks).to be_empty
  end

  it "continues after a recipient failure and logs no event detail or exception message" do
    second = User.create!(name: "Second", email: "lifecycle-notifier-second@example.com", password: "password123!")
    event = GroupLifecycleEvent.create!(group:, actor:, event_type: :operations_closed, detail: "PRIVATE_DETAIL")
    allow(Notification).to receive(:notify_once).and_wrap_original do |method, **attributes|
      raise StandardError, "PRIVATE_ERROR" if attributes.fetch(:recipient) == recipient

      method.call(**attributes)
    end
    expect(Rails.logger).to receive(:error) do |message|
      expect(message).to include("event_id=#{event.id}", "event_type=operations_closed", "recipient_id=#{recipient.id}", "StandardError")
      expect(message).not_to include("PRIVATE_DETAIL", "PRIVATE_ERROR")
    end

    deliver(event, recipient_ids: [ recipient.id, second.id ])
    expect(Notification.where(notifiable: event).pluck(:recipient_id)).to eq([ second.id ])
  end

  it "treats an existing exact notification as a successful uniqueness race" do
    event = GroupLifecycleEvent.create!(group:, actor:, event_type: :opening_requested)
    Notification.create!(recipient:, actor:, action: :group_opening_requested, notifiable: event)
    allow(Notification).to receive(:notify_once).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))
    expect(Rails.logger).not_to receive(:error)

    deliver(event)
    expect(Notification.where(notifiable: event).count).to eq(1)
  end
end
