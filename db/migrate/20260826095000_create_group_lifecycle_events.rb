class CreateGroupLifecycleEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :group_lifecycle_events do |t|
      t.references :group, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.integer :event_type, null: false
      t.text :detail

      t.timestamps
    end

    add_index :group_lifecycle_events, [ :group_id, :created_at, :id ],
              name: "index_group_lifecycle_events_on_group_and_time"
  end
end
