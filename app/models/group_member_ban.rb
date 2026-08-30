class GroupMemberBan < ApplicationRecord
  belongs_to :group
  belongs_to :user

  validates :user_id, uniqueness: { scope: :group_id }
  validate :group_admin_cannot_be_banned

  def current_ban_action
    ModerationAction.where(target: self, action_type: :ban_from_group)
      .order(created_at: :desc, id: :desc)
      .first
  end

  private

  def group_admin_cannot_be_banned
    errors.add(:user, :invalid) if group&.group_admin_id == user_id
  end
end
