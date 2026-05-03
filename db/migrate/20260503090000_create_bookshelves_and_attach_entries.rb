class CreateBookshelvesAndAttachEntries < ActiveRecord::Migration[8.1]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationBookshelf < ActiveRecord::Base
    self.table_name = "bookshelves"
  end

  class MigrationBookshelfEntry < ActiveRecord::Base
    self.table_name = "bookshelf_entries"
  end

  DEFAULT_BOOKSHELF_NAME = "내 책장"
  DEFAULT_VISIBILITY = "public"

  def change
    create_table :bookshelves do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :visibility, null: false, default: DEFAULT_VISIBILITY
      t.timestamps
    end

    add_index :bookshelves, [ :user_id, :name ], unique: true

    add_reference :bookshelf_entries, :bookshelf, foreign_key: true

    reversible do |dir|
      dir.up do
        backfill_default_bookshelves
        backfill_bookshelf_entries
      end
    end

    change_column_null :bookshelf_entries, :bookshelf_id, false
  end

  private

  def backfill_default_bookshelves
    now = Time.current

    MigrationUser.find_each do |user|
      MigrationBookshelf.find_or_create_by!(user_id: user.id, name: DEFAULT_BOOKSHELF_NAME) do |bookshelf|
        bookshelf.visibility = DEFAULT_VISIBILITY
        bookshelf.created_at = now
        bookshelf.updated_at = now
      end
    end
  end

  def backfill_bookshelf_entries
    MigrationBookshelfEntry.where(bookshelf_id: nil).find_each do |entry|
      bookshelf = MigrationBookshelf.find_by!(user_id: entry.user_id, name: DEFAULT_BOOKSHELF_NAME)
      entry.update_columns(bookshelf_id: bookshelf.id)
    end
  end
end
