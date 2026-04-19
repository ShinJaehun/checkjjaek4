class CommentPolicy < ApplicationPolicy
  def create?
    user.present? && PostPolicy.new(user, record.post).show?
  end

  def update?
    user.present? && record.user_id == user.id
  end

  def destroy?
    update?
  end
end
