class AllowNullBookshelfEntryStatus < ActiveRecord::Migration[8.1]
  def change
    change_column_default :bookshelf_entries, :status, from: 0, to: nil
    change_column_null :bookshelf_entries, :status, true
  end
end
