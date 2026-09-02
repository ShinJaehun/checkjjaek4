require "rails_helper"

RSpec.describe ModerationAction, type: :model do
  let(:actor) do
    User.create!(name: "Moderator", email: "moderation-action-actor@example.com", password: "password123!", password_confirmation: "password123!")
  end
  let(:user) do
    User.create!(name: "Member", email: "moderation-action-user@example.com", password: "password123!", password_confirmation: "password123!")
  end
  let(:other_user) do
    User.create!(name: "Other", email: "moderation-action-other@example.com", password: "password123!", password_confirmation: "password123!")
  end
  let(:group) do
    Group.create!(lifecycle_status: :active, group_admin: user, name: "Moderation Group", group_type: :public_group)
  end
  let(:jjaek) { user.jjaeks.create!(content: "Moderation target") }
  let(:comment) { jjaek.comments.create!(user: other_user, content: "Moderation comment") }
  let(:membership) { group.group_memberships.create!(user: other_user, status: :active) }

  def action_for(target:, action_type:, reversal_of: nil)
    public_reason = target.is_a?(Jjaek) && action_type.to_sym == :hide ? "inappropriate_content" : "Public reason"
    moderation_authority = "platform" if target.is_a?(Jjaek) && action_type.to_sym.in?(%i[hide restore])

    described_class.new(
      target:,
      actor:,
      action_type:,
      public_reason:,
      internal_note: "Internal note",
      moderation_authority:,
      reversal_of:
    )
  end

  it "accepts only defined reasons for jjaek hides" do
    Jjaek::MODERATION_HIDE_REASONS.each do |reason|
      action = action_for(target: jjaek, action_type: :hide)
      action.public_reason = reason

      expect(action).to be_valid
    end

    action = action_for(target: jjaek, action_type: :hide)
    action.public_reason = "undefined_reason"
    expect(action).not_to be_valid
  end

  it "requires a stored authority for jjaek hide and restore actions" do
    hide = action_for(target: jjaek, action_type: :hide)
    hide.moderation_authority = nil
    expect(hide).not_to be_valid

    hide.moderation_authority = "group"
    expect(hide).to be_valid

    restore = action_for(target: jjaek, action_type: :restore, reversal_of: hide.tap(&:save!))
    restore.moderation_authority = "unknown"
    expect(restore).not_to be_valid
  end

  it "allows supported original moderation actions" do
    expect(action_for(target: user, action_type: :suspend)).to be_valid
    expect(action_for(target: group, action_type: :suspend_group_operation)).to be_valid
    expect(action_for(target: jjaek, action_type: :hide)).to be_valid
    expect(action_for(target: comment, action_type: :hide)).to be_valid
    expect(action_for(target: membership, action_type: :suspend_activity)).to be_valid
    ban = GroupMemberBan.create!(group:, user: other_user)
    expect(action_for(target: ban, action_type: :ban_from_group)).to be_valid
  end

  it "restores a group operation suspension with a matching action" do
    suspension = action_for(target: group, action_type: :suspend_group_operation).tap(&:save!)
    restore = action_for(target: group, action_type: :restore_group_operation, reversal_of: suspension)

    expect(restore).to be_valid
    expect(action_for(target: group, action_type: :restore_group_operation)).not_to be_valid
  end

  it "stores group-member attribution and validates a matching unban reversal" do
    ban = GroupMemberBan.create!(group:, user: other_user)
    original = action_for(target: ban, action_type: :ban_from_group).tap(&:save!)
    reversal = action_for(target: ban, action_type: :unban_from_group, reversal_of: original)

    expect(original).to have_attributes(membership_group_id: group.id, membership_user_id: other_user.id)
    expect(reversal).to be_valid
    expect(action_for(target: ban, action_type: :unban_from_group)).not_to be_valid
  end

  it "does not set membership attribution for other target types" do
    action = action_for(target: user, action_type: :suspend).tap(&:save!)

    expect(action).to have_attributes(membership_group_id: nil, membership_user_id: nil)
  end

  it "rejects membership attribution that does not match the target" do
    action = action_for(target: membership, action_type: :suspend_activity)
    action.membership_user_id = actor.id

    expect(action).not_to be_valid
    expect(action.errors[:membership_user_id]).to be_present
  end

  it "restores a membership activity suspension with a separate matching action" do
    suspension = action_for(target: membership, action_type: :suspend_activity).tap(&:save!)
    restore = action_for(target: membership, action_type: :restore_activity, reversal_of: suspension)

    expect(restore).to be_valid
    expect(action_for(target: membership, action_type: :restore)).not_to be_valid
    expect(action_for(target: membership, action_type: :restore_activity)).not_to be_valid
  end

  it "requires a public reason and actor" do
    without_reason = action_for(target: user, action_type: :suspend)
    without_reason.public_reason = ""
    without_actor = action_for(target: user, action_type: :suspend)
    without_actor.actor = nil

    expect(without_reason).not_to be_valid
    expect(without_actor).not_to be_valid
  end

  it "rejects unsupported target and action combinations" do
    expect(action_for(target: user, action_type: :hide)).not_to be_valid
    expect(action_for(target: jjaek, action_type: :suspend)).not_to be_valid
    expect(action_for(target: Book.create!(title: "Unsupported", authors_text: "Author"), action_type: :hide)).not_to be_valid
  end

  it "requires restore actions to reference a matching original action" do
    user_suspension = action_for(target: user, action_type: :suspend).tap(&:save!)
    jjaek_hiding = action_for(target: jjaek, action_type: :hide).tap(&:save!)

    expect(action_for(target: user, action_type: :restore)).not_to be_valid
    expect(action_for(target: user, action_type: :restore, reversal_of: user_suspension)).to be_valid
    expect(action_for(target: jjaek, action_type: :restore, reversal_of: jjaek_hiding)).to be_valid
  end

  it "does not allow original actions to reference a reversal" do
    user_suspension = action_for(target: user, action_type: :suspend).tap(&:save!)

    expect(action_for(target: user, action_type: :suspend, reversal_of: user_suspension)).not_to be_valid
    expect(action_for(target: jjaek, action_type: :hide, reversal_of: user_suspension)).not_to be_valid
  end

  it "rejects a reversal for another target or a restore action" do
    user_suspension = action_for(target: user, action_type: :suspend).tap(&:save!)
    restore = action_for(target: user, action_type: :restore, reversal_of: user_suspension).tap(&:save!)

    expect(action_for(target: other_user, action_type: :restore, reversal_of: user_suspension)).not_to be_valid
    expect(action_for(target: user, action_type: :restore, reversal_of: restore)).not_to be_valid
  end

  it "does not allow the same original action to be restored twice" do
    suspension = action_for(target: user, action_type: :suspend).tap(&:save!)
    action_for(target: user, action_type: :restore, reversal_of: suspension).save!

    expect(action_for(target: user, action_type: :restore, reversal_of: suspension)).not_to be_valid
  end

  it "does not allow persisted audit rows to be updated or destroyed" do
    action = action_for(target: user, action_type: :suspend).tap(&:save!)

    expect { action.update!(public_reason: "Replacement reason") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { action.update_columns(public_reason: "Replacement reason") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { action.touch }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { action.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { action.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)

    action.reload
    expect(action.public_reason).to eq("Public reason")
    expect(action).to be_persisted
  end

  it "preserves the audit row after a target jjaek is hard deleted" do
    target_id = jjaek.id
    action = action_for(target: jjaek, action_type: :hide).tap(&:save!)

    expect { jjaek.destroy! }.to change(Jjaek, :count).by(-1)

    action.reload
    expect(action.target_type).to eq("Jjaek")
    expect(action.target_id).to eq(target_id)
    expect(action.actor).to eq(actor)
    expect(action.public_reason).to eq("inappropriate_content")
  end

  it "preserves the audit row after a target membership is deleted" do
    suspension = action_for(target: membership, action_type: :suspend_activity).tap(&:save!)
    restore = action_for(target: membership, action_type: :restore_activity, reversal_of: suspension).tap(&:save!)

    membership.destroy!

    suspension.reload
    restore.reload
    expect(suspension).to have_attributes(
      target_type: "GroupMembership",
      target_id: membership.id,
      membership_group_id: group.id,
      membership_user_id: other_user.id,
      actor:,
      public_reason: "Public reason",
      internal_note: "Internal note"
    )
    expect(restore).to have_attributes(
      membership_group_id: group.id,
      membership_user_id: other_user.id,
      reversal_of: suspension
    )
    expect(described_class.for_membership_group(group)).to include(suspension, restore)
  end

  it "allows legacy membership audit rows without recoverable attribution to be read" do
    described_class.insert!({
      target_type: "GroupMembership",
      target_id: -1,
      actor_id: actor.id,
      action_type: described_class.action_types.fetch("suspend_activity"),
      public_reason: "Legacy",
      created_at: Time.current,
      updated_at: Time.current
    })

    action = described_class.find_by!(public_reason: "Legacy")
    expect(action).to have_attributes(membership_group_id: nil, membership_user_id: nil)
  end
end
