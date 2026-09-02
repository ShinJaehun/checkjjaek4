require "rails_helper"

RSpec.describe Jjaeks::Restore do
  let(:author) { User.create!(name: "Author", email: "restore-author@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Admin", email: "restore-admin@example.com", password: "password123!", global_admin: true) }
  let(:jjaek) { author.jjaeks.create!(content: "Restore target", visibility: :book_friends) }

  def hide!(reason: "spam_advertising")
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: reason).call!
    jjaek.current_hide_action
  end

  it "restores the current hide with a separate audit reason" do
    hide = hide!

    described_class.new(
      jjaek,
      actor: admin,
      public_reason: "검토 결과 복구",
      internal_note: "RESTORE INTERNAL NOTE"
    ).call!

    restore = jjaek.moderation_actions.action_type_restore.sole
    expect(jjaek.reload).to have_attributes(hidden_at: nil, visibility: "book_friends", deleted_at: nil)
    expect(hide.reload).to have_attributes(public_reason: "spam_advertising", reversal_of_id: nil)
    expect(restore).to have_attributes(
      actor: admin,
      public_reason: "검토 결과 복구",
      internal_note: "RESTORE INTERNAL NOTE",
      reversal_of: hide
    )
  end

  it "rolls back the state when the restore audit is invalid" do
    hide = hide!

    expect {
      described_class.new(jjaek, actor: admin, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(jjaek.reload).to be_hidden
    expect(jjaek.current_hide_action).to eq(hide)
    expect(jjaek.moderation_actions.action_type_restore).to be_empty
  end

  it "rejects the author, visible records, and an already restored hide" do
    hide = hide!

    expect {
      described_class.new(jjaek, actor: author, public_reason: "Author restore").call!
    }.to raise_error(described_class::InvalidState)

    described_class.new(jjaek, actor: admin, public_reason: "First restore").call!

    expect {
      described_class.new(jjaek, actor: admin, public_reason: "Duplicate restore").call!
    }.to raise_error(described_class::InvalidState)
    expect(hide.reload).to have_attributes(public_reason: "spam_advertising")
  end

  it "preserves author deletion while clearing moderation hiding" do
    jjaek.comments.create!(user: admin, content: "Preserve tombstone")
    hide!
    jjaek.destroy_or_tombstone!

    described_class.new(jjaek, actor: admin, public_reason: "숨김만 해제").call!

    expect(jjaek.reload).to be_deleted
    expect(jjaek).not_to be_hidden
  end

  it "supports repeated hide and restore cycles without reusing an old hide" do
    hide_a = hide!(reason: "inappropriate_content")
    described_class.new(jjaek, actor: admin, public_reason: "Restore A").call!

    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "service_disruption").call!
    hide_b = jjaek.current_hide_action
    described_class.new(jjaek, actor: admin, public_reason: "Restore B").call!

    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    hide_c = jjaek.current_hide_action
    restores = jjaek.moderation_actions.action_type_restore.order(:id)

    expect(restores.map(&:reversal_of)).to eq([ hide_a, hide_b ])
    expect(jjaek.current_hide_action).to eq(hide_c)
    expect(jjaek.moderation_actions.action_type_hide).to contain_exactly(hide_a, hide_b, hide_c)
  end

  it "lets the current group admin restore a previous group admin's hide without an internal note" do
    previous_admin = User.create!(name: "Previous admin", email: "restore-previous-group-admin@example.com", password: "password123!")
    current_admin = User.create!(name: "Current admin", email: "restore-current-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin: previous_admin, name: "Transferred group", group_type: :private_group)
    group.group_memberships.create!(user: current_admin, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group target")
    Jjaeks::Hide.new(group_jjaek, actor: previous_admin, public_reason: "other").call!
    hide = group_jjaek.current_hide_action
    group.transfer_admin_to!(current_admin, by: previous_admin)

    described_class.new(
      group_jjaek,
      actor: current_admin,
      public_reason: "Resolved",
      internal_note: "Must not persist"
    ).call!

    expect(group_jjaek.reload).not_to be_hidden
    expect(group_jjaek.moderation_actions.action_type_restore.sole).to have_attributes(
      actor: current_admin,
      public_reason: "Resolved",
      moderation_authority: "group",
      internal_note: nil,
      reversal_of: hide
    )
  end

  it "does not let a group admin restore a global-admin-originated hide" do
    group_admin = User.create!(name: "Group admin", email: "restore-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Group", group_type: :public_group)
    group_jjaek = author.jjaeks.create!(group:, content: "Global hide")
    Jjaeks::Hide.new(group_jjaek, actor: admin, public_reason: "other").call!

    expect {
      described_class.new(group_jjaek, actor: group_admin, public_reason: "Blocked").call!
    }.to raise_error(described_class::InvalidState)

    expect(group_jjaek.reload).to be_hidden
  end

  it "keeps global admin restore and internal notes for a group-admin-originated hide" do
    group_admin = User.create!(name: "Group admin", email: "restore-global-override-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Group", group_type: :public_group)
    group_jjaek = author.jjaeks.create!(group:, content: "Group hide")
    Jjaeks::Hide.new(group_jjaek, actor: group_admin, public_reason: "other").call!
    hide = group_jjaek.current_hide_action

    described_class.new(
      group_jjaek,
      actor: admin,
      public_reason: "Platform override",
      internal_note: "Reviewed by platform"
    ).call!

    expect(group_jjaek.reload).not_to be_hidden
    expect(group_jjaek.moderation_actions.action_type_restore.sole).to have_attributes(
      actor: admin,
      public_reason: "Platform override",
      moderation_authority: "platform",
      internal_note: "Reviewed by platform",
      reversal_of: hide
    )
  end
end
