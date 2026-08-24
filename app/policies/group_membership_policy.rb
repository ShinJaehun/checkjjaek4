class GroupMembershipPolicy < ApplicationPolicy
  def create?
    return false unless own_membership?
    return false if record.group.private_group?

    record.group.public_group? ? record.active? : record.pending?
  end

  def approve?
    user.present? && record.group.owner?(user) && record.pending?
  end

  def reject?
    user.present? && record.group.approval_group? && record.group.owner?(user) && record.pending?
  end

  def invite?
    user.present? && record.group.private_group? && record.group.owner?(user) &&
      record.invited? && record.user_id != user.id
  end

  def accept?
    own_membership? && record.invited?
  end

  def decline?
    own_membership? && record.invited?
  end

  def revoke?
    user.present? && record.group.private_group? && record.group.owner?(user) && record.invited?
  end

  def remove?
    user.present? && record.group.owner?(user) && record.inactive? && record.user_id != user.id
  end

  def deactivate?
    user.present? && record.group.owner?(user) && record.active? && record.user_id != user.id
  end

  def reactivate?
    user.present? && record.group.owner?(user) && record.inactive? && record.user_id != user.id
  end

  def destroy?
    own_membership? && !record.group.owner?(user) && (record.pending? || record.active?)
  end

  private

  def own_membership?
    user.present? && record.user_id == user.id
  end
end
