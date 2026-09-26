require "rails_helper"

RSpec.describe "Group lifecycle notification commit delivery" do
  self.use_transactional_tests = false

  before do
    suffix = SecureRandom.hex(6)
    @actor = User.create!(name: "Admin", email: "lifecycle-commit-admin-#{suffix}@example.com", password: "password123!", global_admin: true)
    @recipient = User.create!(name: "Reader", email: "lifecycle-commit-reader-#{suffix}@example.com", password: "password123!")
    @group = Group.create!(name: "Commit club", group_admin: @recipient, lifecycle_status: :active, group_type: :public_group)
  end

  after do
    event_ids = GroupLifecycleEvent.where(group: @group).pluck(:id)
    Notification.where(notifiable_type: "GroupLifecycleEvent", notifiable_id: event_ids).delete_all
    @group.destroy!
    @recipient.reload.destroy!
    @actor.destroy!
  end

  it "delivers the exact event only after the outer commit" do
    event = nil
    Group.transaction do
      event = GroupLifecycleEvent.create!(group: @group, actor: @actor, event_type: :opening_approved)
      Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids: [ @recipient.id ])
      expect(Notification.where(notifiable: event)).to be_empty
    end

    expect(Notification.find_by!(notifiable: event, recipient: @recipient)).to have_attributes(
      action: "group_opening_approved", actor: @actor
    )
  end

  it "does not deliver an event from a rolled-back transaction" do
    Group.transaction do
      event = GroupLifecycleEvent.create!(group: @group, actor: @actor, event_type: :opening_approved)
      Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids: [ @recipient.id ])
      raise ActiveRecord::Rollback
    end

    expect(GroupLifecycleEvent.where(group: @group)).to be_empty
    expect(Notification.where(recipient: @recipient)).to be_empty
  end

  it "preserves the committed event when notification persistence fails" do
    allow(Notification).to receive(:notify_once).and_raise(ActiveRecord::RecordInvalid.new(Notification.new))
    expect(Rails.logger).to receive(:error).with(/event_type=opening_approved.*recipient_id=#{@recipient.id}.*ActiveRecord::RecordInvalid/)

    event = Group.transaction do
      created = GroupLifecycleEvent.create!(group: @group, actor: @actor, event_type: :opening_approved)
      Notifications::GroupLifecycleNotifier.schedule(event: created, recipient_ids: [ @recipient.id ])
      created
    end

    expect(GroupLifecycleEvent.find(event.id)).to eq(event)
    expect(Notification.where(notifiable: event)).to be_empty
  end
end
