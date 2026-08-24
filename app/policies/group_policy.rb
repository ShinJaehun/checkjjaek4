class GroupPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    return false unless user.present?
    return true unless record.private_group?

    record.active_member?(user)
  end

  def create?
    user.present? && record.owner_id == user.id && record.group_type.in?(Group::USER_CREATABLE_TYPES)
  end

  def read_jjaeks?
    user.present? && (record.public_group? || record.active_member?(user))
  end

  def create_jjaek?
    user.present? && record.active_member?(user)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      active_group_ids = GroupMembership.active.where(user: user).select(:group_id)
      scope.where(group_type: %i[public_group approval_group])
        .or(scope.where(id: active_group_ids))
        .distinct
    end
  end
end
