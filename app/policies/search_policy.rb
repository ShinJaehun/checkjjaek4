class SearchPolicy < ApplicationPolicy
  def show?
    user.present?
  end
end
