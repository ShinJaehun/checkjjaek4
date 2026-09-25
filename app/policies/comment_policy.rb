class CommentPolicy < ApplicationPolicy
  class AdminInventoryScope < Scope
    def resolve
      user&.global_admin? ? scope.all : scope.none
    end
  end

  def view_admin_inventory?
    user.present? && user.global_admin? && record.user_id != user.id
  end

  def view_group_moderation_history?
    return false unless user.present? && !user.global_admin?
    return false if record.user_id == user.id
    return false unless record.jjaek.group.present? && record.jjaek.group.group_admin?(user)

    GroupPolicy.new(user, record.jjaek.group).read_jjaeks?
  end

  def view_original_content?
    return true unless record.hidden?
    return false unless user.present?
    return true if record.user_id == user.id || view_admin_inventory?
    return false unless record.jjaek.group.present? && record.jjaek.group.group_admin?(user)

    GroupPolicy.new(user, record.jjaek.group).read_jjaeks?
  end

  def create?
    return false unless user.present? && !record.jjaek.deleted? && jjaek_policy.visible_for_interaction?
    return true if record.jjaek.group_id.blank?

    record.jjaek.group.active? && record.jjaek.group.activity_allowed_for?(user)
  end

  def update?
    return false unless user.present? && record.user_id == user.id
    return false if record.hidden? || record.jjaek.hidden?
    return true if record.jjaek.group_id.blank?

    jjaek_policy.visible_for_interaction? && record.jjaek.group.activity_allowed_for?(user)
  end

  def destroy?
    user.present? && record.user_id == user.id
  end

  def hide?
    user&.global_admin? && record.user_id != user.id && !record.hidden?
  end

  def restore?
    user&.global_admin? && record.user_id != user.id && record.hidden? && record.current_hide_action.present?
  end

  def hide_as_group_admin?
    group_admin_moderation_context? &&
      record.jjaek.group.active? &&
      !record.user.global_admin? &&
      !record.hidden?
  end

  def restore_as_group_admin?
    group_admin_moderation_context? &&
      (record.jjaek.group.active? || record.jjaek.group.inactive?) &&
      record.hidden? &&
      record.current_hide_action&.group_authority?
  end

  private

  def jjaek_policy
    @jjaek_policy ||= JjaekPolicy.new(user, record.jjaek)
  end

  def group_admin_moderation_context?
    return false unless user.present? && !user.global_admin?
    return false unless record.jjaek.group.present?
    return false unless record.jjaek.group.group_admin?(user)
    return false unless record.jjaek.group.operation_active?
    return false if record.user_id == user.id

    true
  end
end
