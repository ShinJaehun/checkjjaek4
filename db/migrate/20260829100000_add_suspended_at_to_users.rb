class AddSuspendedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :suspended_at, :datetime
    add_index :users, :suspended_at
  end
end
