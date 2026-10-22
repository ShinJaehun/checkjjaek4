class GroupMembership < ApplicationRecord
  class InvalidOrder < StandardError; end

  enum :status, { pending: 0, active: 1, invited: 2 }, default: :pending, validate: true
  enum :moderation_status,
       { normal: 0, activity_suspended: 1 },
       default: :normal,
       prefix: true,
       validate: true

  belongs_to :group
  belongs_to :user

  validates :user_id, uniqueness: { scope: :group_id }
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :user_must_have_active_account, on: :create
  validate :user_must_not_be_banned
  validate :group_admin_must_be_active
  validate :status_transition_must_be_valid

  before_destroy :prevent_group_admin_membership_destroy
  after_save :clear_removal_marker, if: -> { active? && saved_change_to_status? }

  def self.displayed_for(user:, groups:)
    active.where(user:, group_id: groups.select(:id)).joins(:group)
      .order(arel_table[:position].asc.nulls_last, Group.arel_table[:created_at].desc, Group.arel_table[:id].desc)
  end

  def self.reorder_for!(user:, groups:, ordered_ids:)
    unless ordered_ids.is_a?(Array) && ordered_ids.all? { |id| id.to_s.match?(/\A[1-9]\d*\z/) }
      raise InvalidOrder
    end
    ids = ordered_ids.map(&:to_i)

    # Serialize this user's saves without blocking foreign-key references from membership events.
    user.with_lock("FOR NO KEY UPDATE") do
      uncached do
        memberships = displayed_for(user:, groups:).reorder(:id)
          .lock("FOR NO KEY UPDATE OF group_memberships").index_by(&:id)
        raise InvalidOrder unless ids.sort == memberships.keys.sort

        ids.each_with_index do |id, index|
          memberships.fetch(id).update!(position: index + 1)
        end

        # Include memberships added while the positions were being saved in the stale-list check.
        raise InvalidOrder unless ids.sort == displayed_for(user:, groups:).reorder(:id).pluck(:id).sort
      end
    end
  end

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
