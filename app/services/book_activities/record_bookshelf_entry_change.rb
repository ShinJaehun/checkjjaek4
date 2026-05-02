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

      record_status_change
      record_sticker_changes
    end

    private

    attr_reader :bookshelf_entry, :was_new_record, :previous_status, :previous_sticker_definition_ids

    def record_status_change
      current_status = bookshelf_entry.status
      return if previous_status == current_status

      action = current_status.nil? ? :status_cleared : :status_changed
      record_activity(
        action,
        metadata: {
          from_status: previous_status,
          to_status: current_status
        }
      )
    end

    def record_sticker_changes
      current_ids = normalize_ids(bookshelf_entry.sticker_definition_ids)
      added_ids = current_ids - previous_sticker_definition_ids
      removed_ids = previous_sticker_definition_ids - current_ids
      return if added_ids.empty? && removed_ids.empty?

      sticker_definitions = StickerDefinition.where(id: added_ids + removed_ids).index_by(&:id)

      added_ids.each do |sticker_definition_id|
        record_sticker_activity(:sticker_added, sticker_definitions.fetch(sticker_definition_id))
      end

      removed_ids.each do |sticker_definition_id|
        record_sticker_activity(:sticker_removed, sticker_definitions.fetch(sticker_definition_id))
      end
    end

    def record_sticker_activity(action, sticker_definition)
      record_activity(
        action,
        metadata: {
          sticker_definition_id: sticker_definition.id,
          sticker_name: sticker_definition.name
        }
      )
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
