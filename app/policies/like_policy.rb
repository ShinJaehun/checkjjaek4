class LikePolicy < ApplicationPolicy
  def create?
    return false unless user.present? && !record.jjaek.deleted? && jjaek_policy.visible_for_interaction?
    return true if record.jjaek.group_id.blank?

    record.jjaek.group.active? && record.jjaek.group.active_member?(user)
  end

  def destroy?
    user.present? &&
      record.user_id == user.id &&
      jjaek_policy.visible_for_interaction?
  end

  private

  def jjaek_policy
    @jjaek_policy ||= JjaekPolicy.new(user, record.jjaek)
  end
end
