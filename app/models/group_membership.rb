class GroupMembership < ApplicationRecord
  enum :status, { pending: 0, active: 1, invited: 2, inactive: 3 }, default: :pending, validate: true

  belongs_to :group
  belongs_to :user

  validates :user_id, uniqueness: { scope: :group_id }
  validate :owner_must_be_active
  validate :status_transition_must_be_valid

  before_destroy :prevent_owner_membership_destroy

  private

  def owner_must_be_active
    return unless group&.owner_id == user_id
    return if active?

    errors.add(:status, :owner_must_be_active)
  end

  def status_transition_must_be_valid
    return unless persisted? && status_changed?
    return if [status_was, status].in?([
      %w[pending active],
      %w[invited active],
      %w[active inactive],
      %w[inactive active]
    ])

    errors.add(:status, :invalid_transition)
  end

  def prevent_owner_membership_destroy
    return unless group.owner_id == user_id

    errors.add(:base, :owner_membership_cannot_be_destroyed)
    throw :abort
  end
end
