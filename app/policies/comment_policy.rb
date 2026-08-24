class CommentPolicy < ApplicationPolicy
  def create?
    user.present? && record.jjaek.group_id.blank? && JjaekPolicy.new(user, record.jjaek).show?
  end

  def update?
    user.present? && record.jjaek.group_id.blank? && record.user_id == user.id
  end

  def destroy?
    update?
  end
end
