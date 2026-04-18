class LikePolicy < ApplicationPolicy
  def create?
    user.present? && PostPolicy.new(user, record.post).show?
  end

  def destroy?
    create? && record.user_id == user.id
  end
end
