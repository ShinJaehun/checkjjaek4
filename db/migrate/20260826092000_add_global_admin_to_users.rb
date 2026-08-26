class AddGlobalAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :global_admin, :boolean, default: false, null: false
  end
end
