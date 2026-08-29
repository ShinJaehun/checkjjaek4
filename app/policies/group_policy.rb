class GroupPolicy < ApplicationPolicy
  class AdminInventoryScope < Scope
    def resolve
      user&.global_admin? ? scope.all : scope.none
    end
  end

  def index?
    user.present?
  end

  def show?
    return false unless user.present?
    return true if operational_investigator?
    return record.group_admin?(user) if record.pending_approval?
    return member_with_basic_access? if record.inactive?
    return true unless record.private_group?

    member_with_basic_access?
  end

  def create?
    user.present? && record.group_admin_id == user.id && record.group_type.in?(Group::USER_CREATABLE_TYPES)
  end

  def update?
    user.present? && record.group_admin?(user)
  end

  alias_method :edit?, :update?

  def read_jjaeks?
    return false unless user.present?
    return true if operational_investigator?
    return record.active_member?(user) if record.inactive?

    record.active? && (record.public_group? || record.active_member?(user))
  end

  def create_jjaek?
    user.present? && record.active? && record.active_member?(user)
  end

  def view_members?
    user.present? && (record.group_admin?(user) || operational_investigator?)
  end

  def close?
    user.present? && record.active? && record.group_admin?(user)
  end

  def request_reactivation?
    user.present? && record.inactive? && record.group_admin?(user)
  end

  def transfer_admin?
    user.present? && (record.active? || record.inactive?) &&
      (record.group_admin?(user) || operational_investigator?)
  end

  def manage_approvals?
    user.present? && user.global_admin?
  end

  def approve?
    manage_approvals? && record.pending_approval?
  end

  def view_admin_details?
    user.present? && user.global_admin?
  end

  alias_method :view_admin_inventory?, :view_admin_details?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.global_admin?

      accessible_group_ids = GroupMembership.where(user: user, status: %i[active inactive]).select(:group_id)
      active_discoverable = scope.active.where(group_type: %i[public_group approval_group])
      active_or_inactive_memberships = scope.where(lifecycle_status: %i[active inactive], id: accessible_group_ids)
      administered_pending = scope.pending_approval.where(group_admin: user)

      active_discoverable
        .or(active_or_inactive_memberships)
        .or(administered_pending)
        .distinct
    end
  end

  private

  def operational_investigator?
    user.global_admin?
  end

  def member_with_basic_access?
    record.group_memberships.where(user: user, status: %i[active inactive]).exists?
  end
end
