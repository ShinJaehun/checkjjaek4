class CreateGroupMembershipEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :group_membership_events do |t|
      t.references :group, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.integer :event_type, null: false

      t.timestamps
    end

    add_index :group_membership_events, [ :group_id, :created_at, :id ],
              name: "index_group_membership_events_on_group_and_time"
  end
end
