class GroupMembershipPolicy < ApplicationPolicy
  def create?
    return false unless record.group.active? && record.group.operation_active?
    return false unless own_membership?
    return false if record.group.private_group?
    return false if record.group.member_banned?(record.user)

    record.group.public_group? ? record.active? : record.pending?
  end

  def approve?
    record.group.active? && record.group.operation_active? && user.present? && record.group.group_admin?(user) && record.pending? &&
      !record.group.member_banned?(record.user)
  end

  def reject?
    user.present? && record.group.operation_active? && record.group.approval_group? && record.group.group_admin?(user) && record.pending?
  end

  def invite?
    record.group.active? && record.group.operation_active? && user.present? && record.group.private_group? && record.group.group_admin?(user) &&
      record.invited? && record.user&.active_account? && record.user_id != user.id &&
      !record.group.member_banned?(record.user)
  end

  def accept?
    record.group.active? && record.group.operation_active? && record.user.active_account? && own_membership? && record.invited? &&
      !record.group.member_banned?(record.user)
  end

  def decline?
    own_membership? && record.invited?
  end

  def revoke?
    user.present? && record.group.operation_active? && record.group.private_group? && record.group.group_admin?(user) && record.invited?
  end

  def remove?
    user.present? && record.group.operation_active? && record.group.group_admin?(user) && record.active? && record.user_id != user.id
  end

  def suspend_activity?
    record.group.operation_active? && moderation_actor? && record.active? && record.moderation_status_normal? && !group_admin_membership?
  end

  def restore_activity?
    record.group.operation_active? && moderation_actor? && record.activity_suspended? && !group_admin_membership?
  end

  def ban_from_group?
    record.group.active? && record.group.operation_active? && record.group.group_admin?(user) && record.user_id != user.id &&
      (record.pending? || record.invited? || record.active?)
  end

  def destroy?
    own_membership? && !record.group.group_admin?(user) && (record.pending? || record.active?)
  end

  private

  def own_membership?
    user.present? && record.user_id == user.id
  end

  def moderation_actor?
    user.present? && record.group.group_admin?(user)
  end

  def group_admin_membership?
    record.user_id == record.group.group_admin_id
  end
end
