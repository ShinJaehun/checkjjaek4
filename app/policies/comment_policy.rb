class CommentPolicy < ApplicationPolicy
  class AdminInventoryScope < Scope
    def resolve
      user&.global_admin? ? scope.all : scope.none
    end
  end

  def view_admin_inventory?
    user.present? && user.global_admin?
  end

  def create?
    return false unless user.present? && !record.jjaek.deleted? && JjaekPolicy.new(user, record.jjaek).show?
    return true if record.jjaek.group_id.blank?

    record.jjaek.group.active? && record.jjaek.group.active_member?(user)
  end

  def update?
    return false unless user.present? && record.user_id == user.id
    return true if record.jjaek.group_id.blank?

    JjaekPolicy.new(user, record.jjaek).show? && record.jjaek.group.active_member?(user)
  end

  def destroy?
    user.present? && record.user_id == user.id
  end
end
