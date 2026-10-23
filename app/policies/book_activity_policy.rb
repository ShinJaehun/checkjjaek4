class BookActivityPolicy < ApplicationPolicy
  def show?
    return false unless user.present? && record.added_to_shelf? && record.bookshelf_entry.present?
    return true if record.user_id == user.id

    return false unless user.book_friend?(record.user)

    !record.bookshelf_entry.bookshelf.visibility_private?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      visible_additions.where(user_id: [ user.id, *BookFriendship.connected_ids_for(user) ])
    end

    private

    def visible_additions
      additions = scope.added_to_shelf.joins(bookshelf_entry: :bookshelf)
      additions.where(user_id: user.id)
        .or(additions.where(bookshelves: { visibility: %w[public book_friends] }))
    end
  end

  class FeedScope < Scope
    def resolve
      return scope.none unless user.present?

      followed_friend_ids = user.followee_ids & BookFriendship.connected_ids_for(user)
      visible_additions.where(user_id: [ user.id, *followed_friend_ids ])
    end
  end

  class ProfileScope < Scope
    def resolve
      return scope.none unless user.present?

      super
    end
  end

  class BookFriendScope < Scope
    def resolve
      return scope.none unless user.present?

      scope.joins(bookshelf_entry: :bookshelf)
        .where(user_id: BookFriendship.connected_ids_for(user), bookshelves: { visibility: %w[public book_friends] })
    end
  end
end
