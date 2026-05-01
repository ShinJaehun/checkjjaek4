class NotificationPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      scope.where(recipient: user)
    end
  end
end
