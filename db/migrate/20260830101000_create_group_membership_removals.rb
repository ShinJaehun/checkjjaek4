class CreateGroupMembershipRemovals < ActiveRecord::Migration[8.1]
  def change
    create_table :group_membership_removals do |t|
      t.references :group, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :removed_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :group_membership_removals, %i[group_id user_id], unique: true
  end
end
