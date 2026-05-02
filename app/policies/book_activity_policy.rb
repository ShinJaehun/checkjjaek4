class BookActivityPolicy < ApplicationPolicy
  def show?
    return false unless user.present?

    record.user_id == user.id || user.book_friend?(record.user) || false
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      visible_user_ids = [ user.id, *BookFriendship.connected_ids_for(user) ]
      scope.where(user_id: visible_user_ids)
    end
  end
end
