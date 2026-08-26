class AddWithdrawnAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :withdrawn_at, :datetime
    add_index :users, :withdrawn_at

    execute <<~SQL
      UPDATE users
      SET withdrawn_at = updated_at
      WHERE withdrawn_at IS NULL
        AND email LIKE 'withdrawn-%@users.invalid'
    SQL
  end

  def down
    remove_index :users, :withdrawn_at
    remove_column :users, :withdrawn_at
  end
end
