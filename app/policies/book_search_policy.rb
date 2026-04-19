class BookSearchPolicy < ApplicationPolicy
  def show?
    user.present?
  end
end
