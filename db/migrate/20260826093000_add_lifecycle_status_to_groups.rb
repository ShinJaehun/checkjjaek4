class AddLifecycleStatusToGroups < ActiveRecord::Migration[8.1]
  def up
    add_column :groups, :lifecycle_status, :integer, default: 1, null: false
    add_index :groups, :lifecycle_status
    change_column_default :groups, :lifecycle_status, from: 1, to: 0
  end

  def down
    remove_index :groups, :lifecycle_status
    remove_column :groups, :lifecycle_status
  end
end
