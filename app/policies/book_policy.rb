class BookPolicy < ApplicationPolicy
  def show?
    user.present?
  end
end
