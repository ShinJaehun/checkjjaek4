class UserPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  def follow?
    user.present? && record != user
  end
end
