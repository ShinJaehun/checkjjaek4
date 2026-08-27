class GroupMembershipPolicy < ApplicationPolicy
  def create?
    return false unless record.group.active?
    return false unless own_membership?
    return false if record.group.private_group?

    record.group.public_group? ? record.active? : record.pending?
  end

  def approve?
    record.group.active? && user.present? && record.group.group_admin?(user) && record.pending?
  end

  def reject?
    user.present? && record.group.approval_group? && record.group.group_admin?(user) && record.pending?
  end

  def invite?
    record.group.active? && user.present? && record.group.private_group? && record.group.group_admin?(user) &&
      record.invited? && record.user&.active_account? && record.user_id != user.id
  end

  def accept?
    record.group.active? && record.user.active_account? && own_membership? && record.invited?
  end

  def decline?
    own_membership? && record.invited?
  end

  def revoke?
    user.present? && record.group.private_group? && record.group.group_admin?(user) && record.invited?
  end

  def remove?
    user.present? && record.group.group_admin?(user) && record.inactive? && record.user_id != user.id
  end

  def deactivate?
    user.present? && record.group.group_admin?(user) && record.active? && record.user_id != user.id
  end

  def reactivate?
    record.group.active? && user.present? && record.group.group_admin?(user) && record.inactive? && record.user_id != user.id
  end

  def destroy?
    own_membership? && !record.group.group_admin?(user) && (record.pending? || record.active?)
  end

  private

  def own_membership?
    user.present? && record.user_id == user.id
  end
end
