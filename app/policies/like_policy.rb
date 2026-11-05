class LikePolicy < ApplicationPolicy
  def create?
    return false unless user.present? && !record.jjaek.deleted? && jjaek_policy.visible_for_interaction?
    return true if record.jjaek.group_id.blank?

    record.jjaek.group.active? && record.jjaek.group.activity_allowed_for?(user)
  end

  def destroy?
    return false unless user.present? && record.user_id == user.id
    return true if jjaek_policy.cleanup_profile_reactions?

    jjaek_policy.show? && (record.jjaek.hidden? || jjaek_policy.visible_for_interaction?)
  end

  private

  def jjaek_policy
    @jjaek_policy ||= JjaekPolicy.new(user, record.jjaek)
  end
end
