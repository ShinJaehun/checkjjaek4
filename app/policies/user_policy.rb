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

  def show_profile_bookshelf_status?
    %i[self book_friend].include?(profile_access_level)
  end

  def show_profile_jjaeks?
    # 로그인 사용자면 항상 섹션은 보이게 하고, 실제 범위는 scope에서 제어한다.
    user.present?
  end

  def write_profile_jjaek?
    %i[self book_friend].include?(profile_access_level)
  end
end
