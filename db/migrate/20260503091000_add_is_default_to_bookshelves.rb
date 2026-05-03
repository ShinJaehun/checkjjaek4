class AddIsDefaultToBookshelves < ActiveRecord::Migration[8.1]
  class MigrationBookshelf < ActiveRecord::Base
    self.table_name = "bookshelves"
  end

  DEFAULT_BOOKSHELF_NAME = "내 책장"

  def change
    add_column :bookshelves, :is_default, :boolean, null: false, default: false

    reversible do |dir|
      dir.up do
        MigrationBookshelf.reset_column_information
        MigrationBookshelf.where(name: DEFAULT_BOOKSHELF_NAME).update_all(is_default: true)
      end
    end

    add_index :bookshelves,
              :user_id,
              unique: true,
              where: "is_default",
              name: "index_bookshelves_on_user_id_default_unique"
  end
end
