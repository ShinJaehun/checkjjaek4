require "rails_helper"

RSpec.describe Notification, type: :model do
  let(:recipient) { User.create!(name: "Recipient", email: "notification-recipient@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:actor) { User.create!(name: "Actor", email: "notification-actor@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:jjaek) { actor.jjaeks.create!(content: "Notification source") }

  it "requires recipient, actor, action, and notifiable" do
    notification = described_class.new

    expect(notification).not_to be_valid
    expect(notification.errors[:recipient]).to be_present
    expect(notification.errors[:actor]).to be_present
    expect(notification.errors[:action]).to be_present
    expect(notification.errors[:notifiable]).to be_present
  end

  it "treats nil read_at as unread" do
    notification = described_class.create!(
      recipient:,
      actor:,
      action: :profile_jjaek_created,
      notifiable: jjaek
    )

    expect(notification).to be_unread
  end

  it "returns only unread notifications from unread scope" do
    unread = described_class.create!(recipient:, actor:, action: :profile_jjaek_created, notifiable: jjaek)
    read = described_class.create!(recipient:, actor:, action: :requote_created, notifiable: actor.jjaeks.create!(content: "Read"), read_at: Time.current)

    expect(described_class.unread).to include(unread)
    expect(described_class.unread).not_to include(read)
  end

  it "orders recent notifications first" do
    older = described_class.create!(recipient:, actor:, action: :profile_jjaek_created, notifiable: jjaek, created_at: 2.days.ago)
    newer = described_class.create!(recipient:, actor:, action: :requote_created, notifiable: actor.jjaeks.create!(content: "Newer"), created_at: 1.day.ago)

    expect(described_class.recent).to eq([ newer, older ])
  end

  it "does not notify a profile jjaek recipient when the jjaek is not visible to them" do
    hidden_jjaek = actor.jjaeks.build(
      target_user: recipient,
      content: "Hidden profile context",
      visibility: :private_jjaek
    )
    hidden_jjaek.save!(validate: false)

    expect {
      described_class.notify_profile_jjaek_created(hidden_jjaek)
    }.not_to change(described_class, :count)
  end

  it "notifies a group Jjaek author only while the source is visible" do
    group_admin = User.create!(name: "Group admin", email: "notification-group-admin@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Notifications", group_type: :private_group)
    author_membership = group.group_memberships.create!(user: recipient, status: :active)
    group.group_memberships.create!(user: actor, status: :active)
    group_jjaek = recipient.jjaeks.create!(group:, content: "Group source")
    visible_comment = group_jjaek.comments.create!(user: actor, content: "Visible")

    expect {
      described_class.notify_comment_created(visible_comment)
    }.to change(described_class, :count).by(1)

    author_membership.update!(status: :inactive)
    hidden_comment = group_jjaek.comments.create!(user: actor, content: "Hidden")
    expect {
      described_class.notify_comment_created(hidden_comment)
    }.not_to change(described_class, :count)
  end

  it "does not notify an author about their own group comment" do
    group = Group.create!(lifecycle_status: :active, group_admin: recipient, name: "Own comments", group_type: :public_group)
    group_jjaek = recipient.jjaeks.create!(group:, content: "Own source")
    own_comment = group_jjaek.comments.create!(user: recipient, content: "Own")

    expect {
      described_class.notify_comment_created(own_comment)
    }.not_to change(described_class, :count)
  end
end
