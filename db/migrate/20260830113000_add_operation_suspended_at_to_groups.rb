class AddOperationSuspendedAtToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :operation_suspended_at, :datetime
  end
end
