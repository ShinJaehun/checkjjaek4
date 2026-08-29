class JjaekPolicy < ApplicationPolicy
  class AdminInventoryScope < Scope
    def resolve
      user&.global_admin? ? scope.all : scope.none
    end
  end

  def view_admin_inventory?
    user.present? && user.global_admin?
  end

  def show?
    return true if user&.global_admin?

    visible_for_interaction?
  end

  def visible_for_interaction?
    user.present? && context_visible_to_user? && quoted_jjaek_visible_to_user?
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
    return false unless user.present? && record.user_id == user.id && !record.deleted?
    return true if record.group_id.blank?

    record.group.activity_allowed_for?(user)
  end

  def destroy?
    user.present? && record.user_id == user.id && !record.deleted?
  end

  class MembershipAwareScope < ApplicationPolicy::Scope
    private

    def readable_member_group_ids
      GroupMembership.active
        .joins(:group)
        .where(user: user, groups: { lifecycle_status: %i[active inactive] })
        .select(:group_id)
    end
  end

  class Scope < MembershipAwareScope
    def resolve
      return scope.none unless user.present?

      with_visible_quoted_jjaeks(visible_records)
    end

    private

    def visible_records
      friend_ids = BookFriendship.connected_ids_for(user)
      personal_records = scope.where(group_id: nil)
        .where(user_id: user.id)
        .or(scope.where(group_id: nil, target_user_id: user.id).where.not(visibility: Jjaek.visibilities[:private_jjaek]))
        .or(scope.where(group_id: nil, visibility: Jjaek.visibilities[:public_jjaek]))
        .or(scope.where(group_id: nil, user_id: friend_ids, visibility: Jjaek.visibilities[:book_friends]))

      public_group_ids = Group.active.public_group.select(:id)
      group_records = scope.where(group_id: public_group_ids)
        .or(scope.where(group_id: readable_member_group_ids))

      personal_records.or(group_records)
    end

    def with_visible_quoted_jjaeks(records)
      visible_quoted_jjaek_ids = visible_records.select(:id)
      deleted_source_requotes = records.where(user_id: user.id).where.not(quoted_source_deleted_at: nil)

      records
        .where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
        .or(records.where(quoted_jjaek_id: visible_quoted_jjaek_ids))
        .or(deleted_source_requotes)
    end
  end

  class GroupContentScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.global_admin?

      JjaekPolicy::Scope.new(user, scope).resolve
    end
  end

  class ProfileScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.global_admin?

      visible_jjaek_ids = JjaekPolicy::Scope.new(user, Jjaek.all).resolve.select(:id)
      scope.where(id: visible_jjaek_ids)
    end
  end

  class FeedScope < MembershipAwareScope
    def resolve
      return scope.none unless user.present?

      with_visible_quoted_jjaeks(feed_records)
    end

    private

    def feed_records
      followee_ids = user.followee_ids
      friend_ids = BookFriendship.connected_ids_for(user)

      personal_records = scope
        .where(group_id: nil, user_id: user.id)
        .or(scope.where(group_id: nil, target_user_id: user.id).where.not(visibility: Jjaek.visibilities[:private_jjaek]))
        .or(scope.where(group_id: nil, user_id: followee_ids, visibility: Jjaek.visibilities[:public_jjaek]))
        .or(scope.where(group_id: nil, user_id: friend_ids, visibility: Jjaek.visibilities[:book_friends]))

      personal_records.or(scope.where(group_id: readable_member_group_ids))
    end

    def with_visible_quoted_jjaeks(records)
      visible_quoted_jjaek_ids = Scope.new(user, scope).resolve.select(:id)
      deleted_source_requotes = records.where(user_id: user.id).where.not(quoted_source_deleted_at: nil)

      records
        .where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
        .or(records.where(quoted_jjaek_id: visible_quoted_jjaek_ids))
        .or(deleted_source_requotes)
    end
  end

  private

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
