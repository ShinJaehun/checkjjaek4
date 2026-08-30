class CreateGroupMemberBans < ActiveRecord::Migration[8.1]
  def change
    create_table :group_member_bans do |t|
      t.references :group, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :group_member_bans, [ :group_id, :user_id ], unique: true
  end
end
