class BookNoteImagePolicy < ApplicationPolicy
  def create?
    owned? && BookshelfEntry.exists?(user_book_id: record.user_book_id)
  end

  def show?
    return false unless owned?

    record.temporary_available? || (record.attached? && record.book_note&.user_book_id == record.user_book_id)
  end

  private

  def owned?
    user&.active_account? && !user.suspended? && record.user_id == user.id && record.user_book&.user_id == user.id
  end
end
