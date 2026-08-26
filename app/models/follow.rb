class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User", inverse_of: :active_follows
  belongs_to :followee, class_name: "User", inverse_of: :passive_follows

  validates :followee_id, uniqueness: { scope: :follower_id }
  validate :followee_is_not_follower
  validate :accounts_must_be_active, on: :create

  private

  def accounts_must_be_active
    errors.add(:base, :invalid) unless follower&.active_account? && followee&.active_account?
  end

  def followee_is_not_follower
    return if follower_id.blank? || followee_id.blank?
    return unless follower_id == followee_id

    errors.add(:followee_id, :invalid)
  end
end
