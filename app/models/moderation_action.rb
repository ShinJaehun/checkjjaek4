class ModerationAction < ApplicationRecord
  TARGET_ACTIONS = {
    "User" => %w[suspend restore],
    "Group" => %w[suspend restore],
    "Jjaek" => %w[hide restore],
    "Comment" => %w[hide restore]
  }.freeze

  enum :action_type,
       { suspend: 0, hide: 1, restore: 2 },
       prefix: true,
       validate: true

  belongs_to :target, polymorphic: true
  belongs_to :actor, class_name: "User"
  belongs_to :reversal_of, class_name: "ModerationAction", optional: true

  validates :public_reason, presence: true
  validates :reversal_of_id, uniqueness: true, allow_nil: true
  validate :action_type_must_match_target
  validate :reversal_must_match_action

  def readonly?
    persisted? || super
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is append-only" if persisted?

    super
  end

  private

  def action_type_must_match_target
    return if TARGET_ACTIONS.fetch(target_type, []).include?(action_type)

    errors.add(:action_type, :invalid)
  end

  def reversal_must_match_action
    if action_type_restore?
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

    expected_action_type = %w[User Group].include?(target_type) ? "suspend" : "hide"
    same_target = reversal_of.target_type == target_type && reversal_of.target_id == target_id

    errors.add(:reversal_of, :invalid) unless same_target && reversal_of.action_type == expected_action_type
  end

end
