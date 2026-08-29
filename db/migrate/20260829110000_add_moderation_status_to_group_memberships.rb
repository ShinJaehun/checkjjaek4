class AddModerationStatusToGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :group_memberships, :moderation_status, :integer, default: 0, null: false
    add_index :group_memberships, :moderation_status
  end
end
