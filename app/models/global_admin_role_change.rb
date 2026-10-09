class GlobalAdminRoleChange < ApplicationRecord
  enum :action, { grant: 0, revoke: 1 }, validate: true

  belongs_to :user

  validates :reason, :operator_account, :server_hostname, :execution_id, presence: true
  validates :operator_uid, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :transition_matches_action

  def readonly?
    persisted? || super
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is append-only" if persisted?

    super
  end

  private

  def transition_matches_action
    valid_transition = (grant? && global_admin_before == false && global_admin_after == true) ||
      (revoke? && global_admin_before == true && global_admin_after == false)
    errors.add(:base, :invalid) unless valid_transition
  end
end
