class CreateGlobalAdminRoleChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :global_admin_role_changes do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :action, null: false
      t.boolean :global_admin_before, null: false
      t.boolean :global_admin_after, null: false
      t.text :reason, null: false
      t.bigint :operator_uid, null: false
      t.string :operator_account, null: false
      t.string :server_hostname, null: false
      t.string :execution_id, null: false
      t.datetime :created_at, null: false
    end

    add_index :global_admin_role_changes, :execution_id, unique: true
    add_index :global_admin_role_changes, [ :user_id, :created_at, :id ],
              name: "index_global_admin_role_changes_on_user_and_time"
    add_check_constraint :global_admin_role_changes,
                         "(action = 0 AND global_admin_before = FALSE AND global_admin_after = TRUE) OR " \
                         "(action = 1 AND global_admin_before = TRUE AND global_admin_after = FALSE)",
                         name: "global_admin_role_changes_valid_transition"
  end
end
