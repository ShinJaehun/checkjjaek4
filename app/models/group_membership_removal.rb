class GroupMembershipRemoval < ApplicationRecord
  belongs_to :group
  belongs_to :user
  belongs_to :removed_by, class_name: "User", inverse_of: :performed_group_membership_removals

  validates :user_id, uniqueness: { scope: :group_id }
end
