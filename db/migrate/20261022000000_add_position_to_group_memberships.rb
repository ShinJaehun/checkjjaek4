class AddPositionToGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :group_memberships, :position, :integer
  end
end
