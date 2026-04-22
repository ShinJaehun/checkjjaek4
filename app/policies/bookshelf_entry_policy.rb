class BookshelfEntryPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    create?
  end

  def create?
    user.present? && record.user_id == user.id
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      visible_user_ids = [ user.id ] + BookFriendship.connected_ids_for(user)
      scope.where(user_id: visible_user_ids)
    end
  end
end
