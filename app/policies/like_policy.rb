class LikePolicy < ApplicationPolicy
  def create?
    return false unless user.present? && !record.jjaek.deleted? && JjaekPolicy.new(user, record.jjaek).show?
    return true if record.jjaek.group_id.blank?

    record.jjaek.group.active? && record.jjaek.group.active_member?(user)
  end

  def destroy?
    user.present? &&
      record.user_id == user.id &&
      JjaekPolicy.new(user, record.jjaek).show?
  end
end
