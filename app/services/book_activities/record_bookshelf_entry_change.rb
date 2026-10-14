module BookActivities
  class RecordBookshelfEntryChange
    def self.call(bookshelf_entry:, was_new_record:)
      return unless was_new_record

      bookshelf_entry.book_activities.create!(
        user: bookshelf_entry.user,
        book: bookshelf_entry.book,
        action: :added_to_shelf
      )
    end
  end
end
