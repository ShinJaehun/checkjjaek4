class BookshelfPolicy < ApplicationPolicy
  def show?
    return false unless user.present?
    return true if record.user_id == user.id
    return true if record.visibility_public?

    record.visibility_book_friends? && user.book_friend?(record.user)
  end

  def create?
    user.present? && record.user_id == user.id
  end

  def update?
    user.present? && record.user_id == user.id && !record.is_default?
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      book_friend_ids = BookFriendship.connected_ids_for(user)

      scope
        .where(user_id: user.id)
        .or(scope.where(user_id: book_friend_ids, visibility: visible_to_book_friends))
        .or(scope.where(visibility: "public"))
    end

    private

    def visible_to_book_friends
      %w[public book_friends]
    end
  end
end
