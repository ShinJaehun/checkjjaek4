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
    return false unless user.present? && !record.jjaek.deleted? && jjaek_policy.visible_for_interaction?
    return true if record.jjaek.group_id.blank?

    record.jjaek.group.active? && record.jjaek.group.activity_allowed_for?(user)
  end

  def update?
    return false unless user.present? && record.user_id == user.id
    return true if record.jjaek.group_id.blank?

    jjaek_policy.visible_for_interaction? && record.jjaek.group.activity_allowed_for?(user)
  end

  def destroy?
    user.present? && record.user_id == user.id
  end

  private

  def jjaek_policy
    @jjaek_policy ||= JjaekPolicy.new(user, record.jjaek)
  end
end
