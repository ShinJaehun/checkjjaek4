class AddHandleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :handle, :string
    add_index :users, "LOWER(handle)", unique: true, where: "handle IS NOT NULL", name: "index_users_on_lower_handle"
  end
end
