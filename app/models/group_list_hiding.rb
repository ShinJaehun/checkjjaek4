class GroupListHiding < ApplicationRecord
  belongs_to :user
  belongs_to :group

  validates :group_id, uniqueness: { scope: :user_id }

  # Called in the same transaction as eligibility changes, even without a page visit.
  def self.restore_eligible_for!(group_id:, user_id: nil)
    eligible_memberships = GroupMembership.active.moderation_status_normal
      .joins(:group).merge(Group.active.where(operation_suspended_at: nil))
      .where(group_id:)
      .where(<<~SQL.squish)
        NOT EXISTS (
          SELECT 1 FROM group_member_bans
          WHERE group_member_bans.group_id = group_memberships.group_id
            AND group_member_bans.user_id = group_memberships.user_id
        )
      SQL
    hidings = where(group_id:, user_id: eligible_memberships.select(:user_id))
    hidings = hidings.where(user_id:) if user_id
    hidings.delete_all
  end
end
