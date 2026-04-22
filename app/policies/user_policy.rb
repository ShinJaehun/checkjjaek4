class UserPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  def follow?
    user.present? && record != user
  end

  def show_bookshelf?
    user.present? && (record == user || user.book_friend?(record) == true)
  end

  def write_jjaek?
    show_bookshelf?
  end
end
