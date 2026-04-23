class JjaekPolicy < ApplicationPolicy
  def show?
    user.present? && visible_to_user? && quoted_jjaek_visible_to_user?
  end

  def create?
    user.present? &&
      record.user_id == user.id &&
      book_context_allowed? &&
      target_user_context_allowed?
  end

  def requote?
    show? && !record.private_jjaek? && !record.requote?
  end

  def update?
    user.present? && record.user_id == user.id
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      with_visible_quoted_jjaeks(visible_records)
    end

    private

    def visible_records
      friend_ids = BookFriendship.connected_ids_for(user)

      scope
        .where(user_id: user.id)
        .or(scope.where(target_user_id: user.id).where.not(visibility: Jjaek.visibilities[:private_jjaek]))
        .or(scope.where(visibility: Jjaek.visibilities[:public_jjaek]))
        .or(scope.where(user_id: friend_ids, visibility: Jjaek.visibilities[:book_friends]))
    end

    def with_visible_quoted_jjaeks(records)
      visible_quoted_jjaek_ids = visible_records.select(:id)

      records
        .where(quoted_jjaek_id: nil)
        .or(records.where(quoted_jjaek_id: visible_quoted_jjaek_ids))
    end
  end

  class FeedScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      with_visible_quoted_jjaeks(feed_records)
    end

    private

    def feed_records
      followee_ids = user.followee_ids
      friend_ids = BookFriendship.connected_ids_for(user)

      scope
        .where(user_id: user.id)
        .or(scope.where(target_user_id: user.id).where.not(visibility: Jjaek.visibilities[:private_jjaek]))
        .or(scope.where(user_id: followee_ids, visibility: Jjaek.visibilities[:public_jjaek]))
        .or(scope.where(user_id: friend_ids, visibility: Jjaek.visibilities[:book_friends]))
    end

    def with_visible_quoted_jjaeks(records)
      visible_quoted_jjaek_ids = Scope.new(user, scope).resolve.select(:id)

      records
        .where(quoted_jjaek_id: nil)
        .or(records.where(quoted_jjaek_id: visible_quoted_jjaek_ids))
    end
  end

  private

  def book_context_allowed?
    return true if record.book_id.blank?

    user.bookshelf_entries.exists?(book_id: record.book_id)
  end

  def target_user_context_allowed?
    return true if record.target_user_id.blank?
    return true if record.target_user_id == user.id
    return false if record.private_jjaek?

    UserPolicy.new(user, record.target_user).write_jjaek?
  end

  def visible_to_user?
    return true if record.user_id == user.id
    return true if record.target_user_id == user.id && !record.private_jjaek?
    return true if record.public_jjaek?
    return false unless record.book_friends?

    user.book_friend?(record.user) || false
  end

  def quoted_jjaek_visible_to_user?
    return true unless record.quoted_jjaek

    self.class.new(user, record.quoted_jjaek).show?
  end
end
