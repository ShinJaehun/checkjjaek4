class ModerationAction < ApplicationRecord
  TARGET_ACTIONS = {
    "User" => %w[suspend restore],
    "Group" => %w[suspend_group_operation restore_group_operation],
    "GroupMembership" => %w[suspend_activity restore_activity],
    "GroupMemberBan" => %w[ban_from_group unban_from_group],
    "Jjaek" => %w[hide restore],
    "Comment" => %w[hide restore]
  }.freeze

  enum :action_type,
       {
         suspend: 0,
         hide: 1,
         restore: 2,
         suspend_activity: 3,
         restore_activity: 4,
         ban_from_group: 5,
         unban_from_group: 6,
         suspend_group_operation: 7,
         restore_group_operation: 8
       },
       prefix: true,
       validate: true

  belongs_to :target, polymorphic: true
  belongs_to :actor, class_name: "User"
  belongs_to :reversal_of, class_name: "ModerationAction", optional: true

  before_validation :set_group_member_attribution, on: :create

  validates :public_reason, presence: true
  validates :reversal_of_id, uniqueness: true, allow_nil: true
  validate :action_type_must_match_target
  validate :jjaek_hide_reason_must_be_allowed
  validate :group_member_attribution_must_match_target, on: :create
  validate :reversal_must_match_action

  scope :for_membership_group, ->(group) {
    where(membership_group_id: group.id)
      .order(created_at: :desc, id: :desc)
  }

  def self.current_suspension_for(user)
    restored_action_ids = where(action_type: :restore).where.not(reversal_of_id: nil).select(:reversal_of_id)

    where(target: user, action_type: :suspend)
      .where.not(id: restored_action_ids)
      .order(created_at: :desc, id: :desc)
      .first
  end

  def self.current_activity_suspension_for(membership)
    restored_action_ids = where(action_type: :restore_activity).where.not(reversal_of_id: nil).select(:reversal_of_id)

    where(target: membership, action_type: :suspend_activity)
      .where.not(id: restored_action_ids)
      .order(created_at: :desc, id: :desc)
      .first
  end

  def self.current_group_operation_suspension_for(group)
    restored_action_ids = where(action_type: :restore_group_operation).where.not(reversal_of_id: nil).select(:reversal_of_id)

    where(target: group, action_type: :suspend_group_operation)
      .where.not(id: restored_action_ids)
      .order(created_at: :desc, id: :desc)
      .first
  end

  def self.current_hide_for(jjaek)
    restored_action_ids = where(action_type: :restore).where.not(reversal_of_id: nil).select(:reversal_of_id)

    where(target: jjaek, action_type: :hide)
      .where.not(id: restored_action_ids)
      .order(created_at: :desc, id: :desc)
      .first
  end

  def readonly?
    persisted? || super
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is append-only" if persisted?

    super
  end

  private

  def jjaek_hide_reason_must_be_allowed
    return unless target_type == "Jjaek" && action_type_hide?
    return if public_reason.in?(Jjaek::MODERATION_HIDE_REASONS)

    errors.add(:public_reason, :inclusion)
  end

  def set_group_member_attribution
    return unless group_member_moderation_target? && target.present?

    self.membership_group_id ||= target.group_id
    self.membership_user_id ||= target.user_id
  end

  def group_member_attribution_must_match_target
    if group_member_moderation_target?
      errors.add(:membership_group_id, :blank) if membership_group_id.blank?
      errors.add(:membership_user_id, :blank) if membership_user_id.blank?
      return unless target.present?

      errors.add(:membership_group_id, :invalid) unless membership_group_id == target.group_id
      errors.add(:membership_user_id, :invalid) unless membership_user_id == target.user_id
    elsif membership_group_id.present? || membership_user_id.present?
      errors.add(:base, :invalid)
    end
  end

  def action_type_must_match_target
    return if TARGET_ACTIONS.fetch(target_type, []).include?(action_type)

    errors.add(:action_type, :invalid)
  end

  def reversal_must_match_action
    if reversal_action?
      validate_restore_source
    elsif reversal_of.present?
      errors.add(:reversal_of, :invalid)
    end
  end

  def validate_restore_source
    unless reversal_of.present? && reversal_of.persisted?
      errors.add(:reversal_of, :blank)
      return
    end

    expected_action_type = if action_type_restore_activity?
      "suspend_activity"
    elsif action_type_unban_from_group?
      "ban_from_group"
    elsif action_type_restore_group_operation?
      "suspend_group_operation"
    elsif target_type == "User"
      "suspend"
    else
      "hide"
    end
    same_target = reversal_of.target_type == target_type && reversal_of.target_id == target_id

    errors.add(:reversal_of, :invalid) unless same_target && reversal_of.action_type == expected_action_type
  end

  def reversal_action?
    action_type_restore? || action_type_restore_activity? || action_type_unban_from_group? ||
      action_type_restore_group_operation?
  end

  def group_member_moderation_target?
    target_type.in?(%w[GroupMembership GroupMemberBan])
  end
end
