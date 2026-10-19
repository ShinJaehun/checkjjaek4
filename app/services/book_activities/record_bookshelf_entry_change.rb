module BookActivities
  class RecordBookshelfEntryChange
    def self.call(bookshelf_entry:, was_new_record:, previous_status: nil, previous_sticker_definition_ids: [])
      if was_new_record
        bookshelf_entry.book_activities.create!(
          user: bookshelf_entry.user,
          book: bookshelf_entry.book,
          action: :added_to_shelf
        )
        return
      end

      current_ids = bookshelf_entry.sticker_definition_ids.map(&:to_i).sort
      previous_ids = Array(previous_sticker_definition_ids).map(&:to_i).sort
      added_ids = current_ids - previous_ids
      removed_ids = previous_ids - current_ids
      return if previous_status == bookshelf_entry.status && added_ids.empty? && removed_ids.empty?

      stickers = StickerDefinition.where(id: added_ids + removed_ids).index_by(&:id)
      bookshelf_entry.book_activities.create!(
        user: bookshelf_entry.user,
        book: bookshelf_entry.book,
        action: :bookshelf_entry_updated,
        metadata: {
          from_status: previous_status,
          to_status: bookshelf_entry.status,
          added_sticker_definition_ids: added_ids,
          added_sticker_names: added_ids.map { |id| stickers.fetch(id).name },
          removed_sticker_definition_ids: removed_ids,
          removed_sticker_names: removed_ids.map { |id| stickers.fetch(id).name }
        }
      )
    end
  end
end
