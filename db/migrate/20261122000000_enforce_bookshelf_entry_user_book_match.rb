class EnforceBookshelfEntryUserBookMatch < ActiveRecord::Migration[8.1]
  FOREIGN_KEY_NAME = "fk_bookshelf_entries_matching_user_book"

  def up
    add_index :user_books, %i[id user_id book_id], unique: true
    add_foreign_key :bookshelf_entries, :user_books,
      column: %i[user_book_id user_id book_id], primary_key: %i[id user_id book_id],
      name: FOREIGN_KEY_NAME, validate: false

    mismatch = connection.select_one(<<~SQL)
      SELECT entries.id AS bookshelf_entry_id, entries.user_book_id,
             entries.user_id AS entry_user_id, entries.book_id AS entry_book_id,
             records.user_id AS record_user_id, records.book_id AS record_book_id
      FROM bookshelf_entries AS entries
      LEFT JOIN user_books AS records ON records.id = entries.user_book_id
      WHERE records.id IS NULL
         OR (entries.user_id, entries.book_id) IS DISTINCT FROM (records.user_id, records.book_id)
      LIMIT 1
    SQL
    if mismatch
      raise ActiveRecord::MigrationError, "BookshelfEntry and UserBook do not match. Inspect this row before retrying: #{mismatch.inspect}"
    end

    validate_foreign_key :bookshelf_entries, name: FOREIGN_KEY_NAME
    remove_foreign_key :bookshelf_entries, :user_books, column: :user_book_id
  end

  def down
    add_foreign_key :bookshelf_entries, :user_books
    remove_foreign_key :bookshelf_entries, name: FOREIGN_KEY_NAME
    remove_index :user_books, %i[id user_id book_id]
  end
end
