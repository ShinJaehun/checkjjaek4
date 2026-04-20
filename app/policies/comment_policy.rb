class CommentPolicy < ApplicationPolicy
  def create?
    user.present? && JjaekPolicy.new(user, record.jjaek).show?
  end

  def update?
    user.present? && record.user_id == user.id
  end

  def destroy?
    update?
  end
end
