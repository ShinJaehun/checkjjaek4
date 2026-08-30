class GroupMemberBanPolicy < ApplicationPolicy
  def destroy?
    user.present? && record.group.active? && record.group.operation_active? && record.group.group_admin?(user)
  end
end
