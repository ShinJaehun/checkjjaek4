class LikePolicy < ApplicationPolicy
  def create?
    user.present? && !record.jjaek.deleted? && record.jjaek.group_id.blank? && JjaekPolicy.new(user, record.jjaek).show?
  end

  def destroy?
    user.present? &&
      record.user_id == user.id &&
      record.jjaek.group_id.blank? &&
      JjaekPolicy.new(user, record.jjaek).show?
  end
end
