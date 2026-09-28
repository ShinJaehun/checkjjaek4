class GroupMemberBanPolicy < ApplicationPolicy
  def unban?
    user.present? && (record.group.active? || record.group.inactive?) && record.group.operation_active? &&
      record.group.group_admin?(user)
  end
end
