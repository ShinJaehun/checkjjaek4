class JjaekPolicy < ApplicationPolicy
  class AdminInventoryScope < Scope
    def resolve
      user&.global_admin? ? scope.all : scope.none
    end
  end

  def view_admin_inventory?
    user.present? && user.global_admin? && record.user_id != user.id
  end

  def view_hidden_content?
    return false unless user.present? && record.hidden?
    return true if record.user_id == user.id
    return true if view_admin_inventory?

    group_admin_can_read_hidden_content?
  end

  def view_group_hidden_placeholder?
    return false unless user.present? && record.hidden?
    return false if view_hidden_content?
    return false unless record.current_hide_action&.group_authority?
    return false unless record.group.present?

    GroupPolicy.new(user, record.group).read_jjaeks?
  end

  def view_group_hidden_read_actions?
    return false unless user.present? && record.hidden? && record.group.present?
    return true if view_group_hidden_placeholder?

    user.global_admin? || record.group.group_admin?(user)
  end

  def view_moderation_internal_note?(moderation_action)
    return false unless moderation_action.present?
    return false if record.user_id == user&.id
    return true if view_admin_inventory?

    moderation_action.group_authority? && view_group_moderation_history?
  end

  def view_group_moderation_history?
    return false unless user.present? && !user.global_admin?
    return false unless record.group.present? && record.group.group_admin_id == user.id
    return false if record.user_id == user.id

    GroupPolicy.new(user, record.group).read_jjaeks?
  end

  def show?
    return view_hidden_content? || view_group_hidden_placeholder? if record.hidden?
    return true if user&.global_admin?

    visible_for_interaction?
  end

  def visible_for_interaction?
    user.present? && !record.hidden? && context_visible_to_user? && quoted_jjaek_visible_to_user?
  end

  def create?
    user.present? &&
      record.user_id == user.id &&
      group_context_allowed? &&
      book_context_allowed? &&
      quoted_context_allowed? &&
      target_user_context_allowed?
  end

  def requote?
    visible_for_interaction? && !record.deleted? && requote_source_context_allowed? && !record.private_jjaek? && !record.requote?
  end

  def create_requote?
    requote? && !already_requoted?
  end

  def update?
    return false unless user.present? && record.user_id == user.id && !record.deleted? && !record.hidden?
    return true if record.group_id.blank?

    record.group.activity_allowed_for?(user)
  end

  def destroy?
    user.present? && record.user_id == user.id && !record.deleted?
  end

  def hide?
    user&.global_admin? && record.user_id != user.id && !record.hidden?
  end

  def restore?
    user&.global_admin? && record.user_id != user.id && record.hidden? && record.current_hide_action.present?
  end

  def hide_as_group_admin?
    group_admin_moderation_context? &&
      !record.user.global_admin? &&
      !record.hidden?
  end

  def restore_as_group_admin?
    group_admin_moderation_context? &&
      record.hidden? &&
      record.current_hide_action.present? &&
      record.current_hide_action.group_authority?
  end

  class MembershipAwareScope < ApplicationPolicy::Scope
    private

    def readable_member_group_ids
      GroupMembership.active
        .joins(:group)
        .where(user: user, groups: { lifecycle_status: %i[active inactive] })
        .select(:group_id)
    end

    def readable_administered_group_ids
      Group.where(group_admin: user, lifecycle_status: %i[active inactive]).select(:id)
    end
  end

  class Scope < MembershipAwareScope
    def resolve
      return scope.none unless user.present?

      visible_scope = scope.visible
      with_visible_quoted_jjaeks(visible_records(visible_scope), visible_scope)
    end

    private

    def visible_records(visible_scope)
      friend_ids = BookFriendship.connected_ids_for(user)
      personal_records = visible_scope.where(group_id: nil)
        .where(user_id: user.id)
        .or(visible_scope.where(group_id: nil, target_user_id: user.id).where.not(visibility: Jjaek.visibilities[:private_jjaek]))
        .or(visible_scope.where(group_id: nil, visibility: Jjaek.visibilities[:public_jjaek]))
        .or(visible_scope.where(group_id: nil, user_id: friend_ids, visibility: Jjaek.visibilities[:book_friends]))

      public_group_ids = Group.active.public_group.select(:id)
      group_records = visible_scope.where(group_id: public_group_ids)
        .or(visible_scope.where(group_id: readable_member_group_ids))

      personal_records.or(group_records)
    end

    def with_visible_quoted_jjaeks(records, visible_scope)
      visible_quoted_jjaek_ids = visible_records(visible_scope).select(:id)
      deleted_source_requotes = records.where(user_id: user.id).where.not(quoted_source_deleted_at: nil)

      records
        .where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
        .or(records.where(quoted_jjaek_id: visible_quoted_jjaek_ids))
        .or(deleted_source_requotes)
    end
  end

  class GroupContentScope < MembershipAwareScope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.global_admin?

      visible_records = JjaekPolicy::Scope.new(user, scope).resolve
      hidden_scope = scope.where(user_id: user.id).where.not(hidden_at: nil)
      public_group_ids = Group.active.public_group.select(:id)
      hidden_own_records = hidden_scope.where(group_id: public_group_ids)
        .or(hidden_scope.where(group_id: readable_member_group_ids))

      hidden_administered_records = scope.where(group_id: readable_administered_group_ids).where.not(hidden_at: nil)
      group_hidden_records = readable_group_hidden_records

      visible_records.or(hidden_own_records).or(hidden_administered_records).or(group_hidden_records)
    end

    private

    def readable_group_hidden_records
      restored_hide_ids = ModerationAction.action_type_restore.where.not(reversal_of_id: nil).select(:reversal_of_id)
      group_hidden_jjaek_ids = ModerationAction.action_type_hide
        .where(target_type: "Jjaek", moderation_authority: "group")
        .where.not(id: restored_hide_ids)
        .select(:target_id)
      hidden_records = scope.where.not(hidden_at: nil).where(id: group_hidden_jjaek_ids)

      public_group_ids = Group.active.public_group.select(:id)
      hidden_records.where(group_id: public_group_ids)
        .or(hidden_records.where(group_id: readable_member_group_ids))
    end
  end

  class ProfileScope < MembershipAwareScope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.global_admin?

      visible_jjaek_ids = JjaekPolicy::Scope.new(user, Jjaek.all).resolve.select(:id)
      visible_records = scope.where(id: visible_jjaek_ids)
      hidden_own_records = hidden_own_records_for_profile

      visible_records.or(hidden_own_records)
    end

    private

    def hidden_own_records_for_profile
      hidden_scope = scope.where(user_id: user.id).where.not(hidden_at: nil)
      public_group_ids = Group.active.public_group.select(:id)

      hidden_scope.where(group_id: nil)
        .or(hidden_scope.where(group_id: public_group_ids))
        .or(hidden_scope.where(group_id: readable_member_group_ids))
    end
  end

  class FeedScope < MembershipAwareScope
    def resolve
      return scope.none unless user.present?

      visible_scope = scope.visible
      visible_records = with_visible_quoted_jjaeks(feed_records(visible_scope), visible_scope)
      hidden_scope = scope.where(user_id: user.id).where.not(hidden_at: nil)
      hidden_own_records = hidden_scope.where(group_id: nil)
        .or(hidden_scope.where(group_id: readable_member_group_ids))

      visible_records.or(hidden_own_records)
    end

    private

    def feed_records(visible_scope)
      followee_ids = user.followee_ids
      friend_ids = BookFriendship.connected_ids_for(user)

      personal_records = visible_scope
        .where(group_id: nil, user_id: user.id)
        .or(visible_scope.where(group_id: nil, target_user_id: user.id).where.not(visibility: Jjaek.visibilities[:private_jjaek]))
        .or(visible_scope.where(group_id: nil, user_id: followee_ids, visibility: Jjaek.visibilities[:public_jjaek]))
        .or(visible_scope.where(group_id: nil, user_id: friend_ids, visibility: Jjaek.visibilities[:book_friends]))

      personal_records.or(visible_scope.where(group_id: readable_member_group_ids))
    end

    def with_visible_quoted_jjaeks(records, visible_scope)
      visible_quoted_jjaek_ids = Scope.new(user, visible_scope).resolve.select(:id)
      deleted_source_requotes = records.where(user_id: user.id).where.not(quoted_source_deleted_at: nil)

      records
        .where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
        .or(records.where(quoted_jjaek_id: visible_quoted_jjaek_ids))
        .or(deleted_source_requotes)
    end
  end

  private

  def group_admin_moderation_context?
    return false unless user.present? && !user.global_admin?
    return false unless record.group.present? && record.group.group_admin?(user)

    record.group.operation_active? &&
      (record.group.active? || record.group.inactive?) &&
      record.user_id != user.id
  end

  def group_admin_can_read_hidden_content?
    view_group_moderation_history?
  end

  def requote_source_context_allowed?
    return true if record.group_id.blank?

    record.group.active? && record.group.public_group?
  end

  def book_context_allowed?
    return true if record.book_id.blank?

    user.bookshelf_entries.exists?(book_id: record.book_id)
  end

  def group_context_allowed?
    return true if record.group_id.blank?

    GroupPolicy.new(user, record.group).create_jjaek?
  end

  def quoted_context_allowed?
    return true if record.quoted_jjaek_id.blank?
    return false if record.group_id.present?

    self.class.new(user, record.quoted_jjaek).requote?
  end

  def target_user_context_allowed?
    return true if record.target_user_id.blank?
    return true if record.target_user_id == user.id
    return false if record.private_jjaek?

    UserPolicy.new(user, record.target_user).write_jjaek?
  end

  def context_visible_to_user?
    return GroupPolicy.new(user, record.group).read_jjaeks? if record.group_id.present?

    visible_to_user?
  end

  def visible_to_user?
    return true if record.user_id == user.id
    return true if record.target_user_id == user.id && !record.private_jjaek?
    return true if record.public_jjaek?
    return false unless record.book_friends?

    user.book_friend?(record.user) || false
  end

  def quoted_jjaek_visible_to_user?
    return record.user_id == user.id if record.quoted_source_deleted?
    return true unless record.quoted_jjaek

    self.class.new(user, record.quoted_jjaek).visible_for_interaction?
  end

  def already_requoted?
    return false unless user.present? && record.persisted?

    Jjaek.exists?(user_id: user.id, quoted_jjaek_id: record.id)
  end
end
