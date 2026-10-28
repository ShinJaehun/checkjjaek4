class GroupPolicy < ApplicationPolicy
  class AdminInventoryScope < Scope
    def resolve
      user&.global_admin? ? scope.all : scope.none
    end
  end

  class MembershipScope < Scope
    def resolve
      return scope.none unless user.present?

      membership_group_ids = GroupMembership.active.where(user: user).select(:group_id)
      scope.where(id: membership_group_ids, lifecycle_status: %i[pending_approval active inactive])
    end
  end

  class CreateJjaekScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      writable_group_ids = GroupMembership.active.moderation_status_normal.where(user: user).select(:group_id)
      scope.active.where(operation_suspended_at: nil, id: writable_group_ids)
    end
  end

  class PastMembershipScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      event_group_ids = GroupMembershipEvent.participations.where(user:).select(:group_id)
      banned_group_ids = GroupMembershipEvent.ban_history_for(user).select(:membership_group_id)
      current_group_ids = GroupMembership.active.where(user:).select(:group_id)
      scope.where(id: event_group_ids).or(scope.where(id: banned_group_ids)).where.not(id: current_group_ids)
    end
  end

  def cleanup_content?
    user.present? && !read_jjaeks? && PastMembershipScope.new(user, Group).resolve.exists?(record.id)
  end

  def hide_from_list?
    return false unless user.present?
    membership = record.group_memberships.active.find_by(user:)
    return PastMembershipScope.new(user, Group).resolve.exists?(record.id) unless membership

    membership.removable_from_list?
  end

  class ReadableContentScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      groups = scope.where.not(lifecycle_status: %i[rejected cancelled])
      return groups if user.global_admin?

      membership_group_ids = GroupMembership.active.where(user:).select(:group_id)
      groups.where(lifecycle_status: %i[active inactive], id: membership_group_ids)
        .or(groups.active.public_group)
    end
  end

  def index?
    user.present?
  end

  def show?
    return false unless user.present?
    return true if operational_investigator?
    return record.group_admin?(user) if record.application_ended?
    return record.group_admin?(user) if record.pending_approval?
    return member_with_basic_access? if record.inactive?
    return true unless record.private_group?

    member_with_basic_access?
  end

  def create?
    user.present? && user.active_account? && record.group_admin_id == user.id && record.group_type.in?(Group::USER_CREATABLE_TYPES)
  end

  def update?
    user.present? && record.operation_active? && record.group_admin?(user)
  end

  alias_method :edit?, :update?

  def read_jjaeks?
    return false unless user.present?
    return false if record.application_ended?
    return true if operational_investigator?
    return record.active_member?(user) if record.inactive?

    record.active? && (record.public_group? || record.active_member?(user))
  end

  def create_jjaek?
    user.present? && record.active? && record.activity_allowed_for?(user)
  end

  def view_members?
    return false unless user.present?
    return true if operational_investigator?

    !record.application_ended? && record.group_admin?(user)
  end

  def view_content_inventory?
    user.present? && record.group_admin?(user) && (record.active? || record.inactive?)
  end

  def close?
    user.present? && record.operation_active? && record.active? && record.group_admin?(user)
  end

  def request_reactivation?
    user.present? && record.operation_active? && record.inactive? && record.group_admin?(user)
  end

  def transfer_admin?
    user.present? && record.operation_active? && (record.active? || record.inactive?) &&
      (record.group_admin?(user) || operational_investigator?)
  end

  def suspend_operation?
    user.present? && user.global_admin? && record.active? && record.operation_active?
  end

  def restore_operation?
    user.present? && user.global_admin? && record.operation_suspended?
  end

  def manage_approvals?
    user.present? && user.global_admin?
  end

  def approve?
    manage_approvals? && record.pending_approval?
  end

  def reject?
    manage_approvals? && (record.pending_opening_application? || record.pending_reactivation_request?)
  end

  def cancel_application?
    user.present? && record.group_admin?(user) && record.pending_opening_application?
  end

  def withdraw_reactivation?
    user.present? && record.group_admin?(user) && record.pending_reactivation_request?
  end

  def view_admin_details?
    user.present? && user.global_admin?
  end

  alias_method :view_admin_inventory?, :view_admin_details?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.global_admin?

      accessible_group_ids = GroupMembership.active.where(user: user).select(:group_id)
      active_discoverable = scope.active.where(group_type: %i[public_group approval_group])
      active_or_inactive_memberships = scope.where(lifecycle_status: %i[active inactive], id: accessible_group_ids)
      administered_applications = scope.where(lifecycle_status: %i[pending_approval rejected cancelled], group_admin: user)

      active_discoverable
        .or(active_or_inactive_memberships)
        .or(administered_applications)
        .distinct
    end
  end

  class NameSearchScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      visible_group_ids = Scope.new(user, scope).resolve.reselect(:id)
      scope.where(id: visible_group_ids).or(scope.active)
    end
  end

  private

  def operational_investigator?
    user.global_admin?
  end

  def member_with_basic_access?
    record.active_member?(user)
  end
end
