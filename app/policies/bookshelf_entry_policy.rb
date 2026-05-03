class BookshelfEntryPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    create?
  end

  def create?
    user.present? && record.user_id == user.id
  end

  def update?
    create?
  end

  def move?
    create?
  end

  def destroy?
    create?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      scope.where(user_id: user.id)
    end
  end

  class ProfileScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      book_friend_ids = BookFriendship.connected_ids_for(user)
      scoped_entries =
        scope
          .joins(:bookshelf)
          .where(bookshelf_entries: { user_id: user.id })
          .or(
            scope
              .joins(:bookshelf)
              .where(
                bookshelf_entries: { user_id: book_friend_ids },
                bookshelves: { visibility: visible_to_book_friends }
              )
          )
          .or(scope.joins(:bookshelf).where(bookshelves: { visibility: "public" }))

      scoped_entries
    end

    private

    def visible_to_book_friends
      %w[public book_friends]
    end
  end
end
