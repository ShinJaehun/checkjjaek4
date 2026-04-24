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

      scope.where(user_id: user.id)
    end
  end

  class ProfileScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      scope
    end
  end
end
