class PostPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present? && record.public_feed?
  end

  def create?
    user.present?
  end

  def update?
    user.present? && record.user_id == user.id
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      followee_ids = user.followee_ids
      scope.where(user_id: [ user.id ] + followee_ids, visibility: Post.visibilities[:public_feed])
    end
  end

  class ProfileScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      scope.where(visibility: Post.visibilities[:public_feed])
    end
  end
end
