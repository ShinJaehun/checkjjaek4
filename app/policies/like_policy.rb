class LikePolicy < ApplicationPolicy
  def create?
    user.present? && JjaekPolicy.new(user, record.jjaek).show?
  end

  def destroy?
    create? && record.user_id == user.id
  end
end
