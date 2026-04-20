class JjaekPolicy < ApplicationPolicy
  def show?
    user.present? && visible_to_user?
  end

  def create?
    user.present? && record.user_id == user.id
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

      friend_ids = BookFriendship.connected_ids_for(user)

      scope
        .where(user_id: user.id)
        .or(scope.where(visibility: Jjaek.visibilities[:public_jjaek]))
        .or(scope.where(user_id: friend_ids, visibility: Jjaek.visibilities[:book_friends]))
    end
  end

  class FeedScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      followee_ids = user.followee_ids
      friend_ids = BookFriendship.connected_ids_for(user)

      scope
        .where(user_id: user.id)
        .or(scope.where(user_id: followee_ids, visibility: Jjaek.visibilities[:public_jjaek]))
        .or(scope.where(user_id: friend_ids, visibility: Jjaek.visibilities[:book_friends]))
    end
  end

  private

  def visible_to_user?
    return true if record.user_id == user.id
    return true if record.public_jjaek?
    return false unless record.book_friends?

    user.book_friend?(record.user)
  end
end
