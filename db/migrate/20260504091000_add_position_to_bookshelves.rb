class AddPositionToBookshelves < ActiveRecord::Migration[8.0]
  class MigrationBookshelf < ApplicationRecord
    self.table_name = "bookshelves"
  end

  def up
    add_column :bookshelves, :position, :integer, null: false, default: 0

    MigrationBookshelf.reset_column_information
    MigrationBookshelf.where(is_default: true).update_all(position: 0)

    MigrationBookshelf.where(is_default: false).distinct.pluck(:user_id).each do |user_id|
      MigrationBookshelf
        .where(user_id: user_id, is_default: false)
        .order(:created_at, :id)
        .each_with_index do |bookshelf, index|
          bookshelf.update_columns(position: index + 1)
        end
    end
  end

  def down
    remove_column :bookshelves, :position
  end
end
