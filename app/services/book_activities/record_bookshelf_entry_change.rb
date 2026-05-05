module BookActivities
  class RecordBookshelfEntryChange
    def self.call(...)
      new(...).call
    end

    def initialize(bookshelf_entry:, was_new_record:, previous_status:, previous_sticker_definition_ids:)
      @bookshelf_entry = bookshelf_entry
      @was_new_record = was_new_record
      @previous_status = previous_status
      @previous_sticker_definition_ids = normalize_ids(previous_sticker_definition_ids)
    end

    def call
      if was_new_record
        record_activity(:added_to_shelf)
        return
      end

      record_update_activity
    end

    private

    attr_reader :bookshelf_entry, :was_new_record, :previous_status, :previous_sticker_definition_ids

    def record_update_activity
      current_status = bookshelf_entry.status
      current_ids = normalize_ids(bookshelf_entry.sticker_definition_ids)
      added_ids = current_ids - previous_sticker_definition_ids
      removed_ids = previous_sticker_definition_ids - current_ids
      status_changed = previous_status != current_status
      return unless status_changed || added_ids.any? || removed_ids.any?

      sticker_definitions = StickerDefinition.where(id: added_ids + removed_ids).index_by(&:id)
      added_stickers = stickers_for(added_ids, sticker_definitions)
      removed_stickers = stickers_for(removed_ids, sticker_definitions)

      record_activity(
        :bookshelf_entry_updated,
        metadata: {
          from_status: previous_status,
          to_status: current_status,
          added_sticker_definition_ids: added_stickers.map(&:id),
          added_sticker_names: added_stickers.map(&:name),
          removed_sticker_definition_ids: removed_stickers.map(&:id),
          removed_sticker_names: removed_stickers.map(&:name)
        }
      )
    end

    def stickers_for(sticker_definition_ids, sticker_definitions)
      sticker_definition_ids.map { |sticker_definition_id| sticker_definitions.fetch(sticker_definition_id) }
    end

    def record_activity(action, metadata: {})
      BookActivity.create!(
        user: bookshelf_entry.user,
        book: bookshelf_entry.book,
        bookshelf_entry: bookshelf_entry,
        action: action,
        metadata: metadata
      )
    end

    def normalize_ids(ids)
      Array(ids).map(&:to_i).sort
    end
  end
end
