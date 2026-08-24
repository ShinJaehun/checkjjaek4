class CommentPolicy < ApplicationPolicy
  def create?
    return false unless user.present? && JjaekPolicy.new(user, record.jjaek).show?
    return true if record.jjaek.group_id.blank?

    record.jjaek.group.active_member?(user)
  end

  def update?
    return false unless user.present? && record.user_id == user.id
    return true if record.jjaek.group_id.blank?

    JjaekPolicy.new(user, record.jjaek).show? && record.jjaek.group.active_member?(user)
  end

  def destroy?
    user.present? && record.user_id == user.id
  end
end
