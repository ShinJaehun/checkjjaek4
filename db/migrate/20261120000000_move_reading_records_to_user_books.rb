class MoveReadingRecordsToUserBooks < ActiveRecord::Migration[8.1]
  def up
    create_table :user_books do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :book, null: false, foreign_key: true
      t.integer :status
      t.timestamps

      t.index [ :user_id, :book_id ], unique: true
    end

    add_reference :bookshelf_entries, :user_book, foreign_key: true, index: { unique: true }

    execute <<~SQL
      INSERT INTO user_books (user_id, book_id, status, created_at, updated_at)
      SELECT user_id, book_id, status, created_at, updated_at
      FROM bookshelf_entries
    SQL

    execute <<~SQL
      UPDATE bookshelf_entries AS entries
      SET user_book_id = user_books.id
      FROM user_books
      WHERE user_books.user_id = entries.user_id AND user_books.book_id = entries.book_id
    SQL
    change_column_null :bookshelf_entries, :user_book_id, false

    rename_table :bookshelf_entry_stickers, :user_book_stickers
    add_reference :user_book_stickers, :user_book, foreign_key: true, index: false
    execute <<~SQL
      UPDATE user_book_stickers AS stickers
      SET user_book_id = entries.user_book_id
      FROM bookshelf_entries AS entries
      WHERE entries.id = stickers.bookshelf_entry_id
    SQL
    change_column_null :user_book_stickers, :user_book_id, false
    add_index :user_book_stickers, [ :user_book_id, :sticker_definition_id ],
      unique: true, name: "index_user_book_stickers_on_book_and_sticker"

    remove_reference :user_book_stickers, :bookshelf_entry, foreign_key: true
    remove_column :bookshelf_entries, :status

    remove_foreign_key :book_activities, :bookshelf_entries
    add_foreign_key :book_activities, :bookshelf_entries, on_delete: :nullify
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Reading records can outlive their bookshelf entries"
  end
end
