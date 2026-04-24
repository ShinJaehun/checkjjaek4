class UserPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  def follow?
    user.present? && record != user
  end

  def show_bookshelf?
    show_profile_bookshelf?
  end

  def write_jjaek?
    write_profile_jjaek?
  end

  def profile_access_level
    return :none unless user.present?
    return :self if record == user
    return :book_friend if user.book_friend?(record)
    return :following if user.follows?(record)

    :none
  end

  def show_profile_bookshelf?
    user.present?
  end

  def show_profile_jjaeks?
    %i[self book_friend following].include?(profile_access_level)
  end

  def write_profile_jjaek?
    %i[self book_friend].include?(profile_access_level)
  end
end
