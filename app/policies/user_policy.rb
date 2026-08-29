class UserPolicy < ApplicationPolicy
  class AdminInventoryScope < Scope
    def resolve
      user&.global_admin? ? scope.all : scope.none
    end
  end

  def view_admin_inventory?
    user.present? && user.global_admin?
  end

  def show?
    user.present?
  end

  def suspend?
    user&.global_admin? && record != user && !record.withdrawn? && !record.suspended?
  end

  def restore?
    user&.global_admin? && !record.withdrawn? && record.suspended?
  end

  def show_library?
    %i[self book_friend].include?(profile_access_level)
  end

  def follow?
    user.present? && user.active_account? && record.active_account? && record != user
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
    operational_profile_read? || %i[self book_friend].include?(profile_access_level)
  end

  def show_profile_jjaeks?
    # 로그인 사용자면 항상 섹션은 보이게 하고, 실제 범위는 scope에서 제어한다.
    user.present?
  end

  def write_profile_jjaek?
    record.active_account? && %i[self book_friend].include?(profile_access_level)
  end

  private

  def operational_profile_read?
    user&.global_admin?
  end
end
