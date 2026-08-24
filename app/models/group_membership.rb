class GroupMembership < ApplicationRecord
  enum :status, { pending: 0, active: 1 }, default: :pending, validate: true

  belongs_to :group
  belongs_to :user

  validates :user_id, uniqueness: { scope: :group_id }
  validate :owner_must_be_active
  validate :active_membership_cannot_return_to_pending

  before_destroy :prevent_owner_membership_destroy

  private

  def owner_must_be_active
    return unless group&.owner_id == user_id
    return if active?

    errors.add(:status, :owner_must_be_active)
  end

  def active_membership_cannot_return_to_pending
    return unless status_changed? && status_was == "active" && pending?

    errors.add(:status, :invalid_transition)
  end

  def prevent_owner_membership_destroy
    return unless group.owner_id == user_id

    errors.add(:base, :owner_membership_cannot_be_destroyed)
    throw :abort
  end
end
