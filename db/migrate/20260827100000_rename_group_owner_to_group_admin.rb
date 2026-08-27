class RenameGroupOwnerToGroupAdmin < ActiveRecord::Migration[8.1]
  def change
    rename_column :groups, :owner_id, :group_admin_id
  end
end
