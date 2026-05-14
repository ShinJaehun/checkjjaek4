class AddPositionToBookshelfEntries < ActiveRecord::Migration[8.1]
  class BookshelfEntry < ActiveRecord::Base
    self.table_name = "bookshelf_entries"
  end

  def up
    add_column :bookshelf_entries, :position, :integer

    BookshelfEntry.reset_column_information
    BookshelfEntry.distinct.pluck(:bookshelf_id).each do |bookshelf_id|
      BookshelfEntry
        .where(bookshelf_id:)
        .order(updated_at: :desc, id: :asc)
        .each_with_index do |entry, index|
          entry.update_columns(position: index + 1)
        end
    end

    change_column_null :bookshelf_entries, :position, false
    add_index :bookshelf_entries, [ :bookshelf_id, :position ]
  end

  def down
    remove_index :bookshelf_entries, [ :bookshelf_id, :position ]
    remove_column :bookshelf_entries, :position
  end
end
