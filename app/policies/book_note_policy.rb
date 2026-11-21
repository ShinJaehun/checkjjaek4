class BookNotePolicy < ApplicationPolicy
  def show?
    user&.active_account? && record.user_book.user_id == user.id
  end

  def create?
    show? && BookshelfEntry.exists?(user_book_id: record.user_book_id)
  end
  alias_method :update?, :create?
  alias_method :destroy?, :create?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.active_account?

      scope.where(user_book: user.user_books)
    end
  end
end
