class ConvertUsersToDevise < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :encrypted_password, :string, null: false, default: ""
    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_column :users, :remember_created_at, :datetime

    execute <<~SQL.squish
      UPDATE users
      SET encrypted_password = password_digest
      WHERE password_digest IS NOT NULL
    SQL

    remove_column :users, :password_digest, :string
    add_index :users, :reset_password_token, unique: true
  end

  def down
    add_column :users, :password_digest, :string, null: false, default: ""

    execute <<~SQL.squish
      UPDATE users
      SET password_digest = encrypted_password
      WHERE encrypted_password IS NOT NULL
    SQL

    remove_index :users, :reset_password_token
    remove_column :users, :remember_created_at, :datetime
    remove_column :users, :reset_password_sent_at, :datetime
    remove_column :users, :reset_password_token, :string
    remove_column :users, :encrypted_password, :string
  end
end
