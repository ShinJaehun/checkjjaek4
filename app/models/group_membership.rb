class GroupMembership < ApplicationRecord
  enum :status, { pending: 0, active: 1, invited: 2 }, default: :pending, validate: true
  enum :moderation_status,
       { normal: 0, activity_suspended: 1 },
       default: :normal,
       prefix: true,
       validate: true

  belongs_to :group
  belongs_to :user

  validates :user_id, uniqueness: { scope: :group_id }
  validate :user_must_have_active_account, on: :create
  validate :user_must_not_be_banned
  validate :group_admin_must_be_active
  validate :status_transition_must_be_valid

  before_destroy :prevent_group_admin_membership_destroy
  after_save :clear_removal_marker, if: -> { active? && saved_change_to_status? }

  def activity_suspended?
    moderation_status_activity_suspended?
  end

  def activity_allowed?
    active? && moderation_status_normal?
  end

  def current_activity_suspension_action
    ModerationAction.current_activity_suspension_for(self)
  end

  private

  def group_admin_must_be_active
    return unless group&.group_admin_id == user_id
    return if active?

    errors.add(:status, :group_admin_must_be_active)
  end

  def user_must_have_active_account
    errors.add(:user, :invalid) unless user&.active_account?
  end

  def user_must_not_be_banned
    return unless group_id && user_id

    errors.add(:user, :invalid) if GroupMemberBan.exists?(group_id:, user_id:)
  end

  def status_transition_must_be_valid
    return unless persisted? && status_changed?
    return if [ status_was, status ].in?([
      %w[pending active],
      %w[invited active]
    ])

    errors.add(:status, :invalid_transition)
  end

  def prevent_group_admin_membership_destroy
    return if destroyed_by_association.present?
    return unless group.active? && group.group_admin_id == user_id

    errors.add(:base, :group_admin_membership_cannot_be_destroyed)
    throw :abort
  end

  def clear_removal_marker
    GroupMembershipRemoval.where(group_id:, user_id:).delete_all
  end
end
