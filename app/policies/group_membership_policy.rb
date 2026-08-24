class GroupMembershipPolicy < ApplicationPolicy
  def create?
    return false unless own_membership?
    return false if record.group.private_group?

    record.group.public_group? ? record.active? : record.pending?
  end

  def approve?
    user.present? && record.group.owner?(user) && record.pending?
  end

  def destroy?
    own_membership? && !record.group.owner?(user)
  end

  private

  def own_membership?
    user.present? && record.user_id == user.id
  end
end
