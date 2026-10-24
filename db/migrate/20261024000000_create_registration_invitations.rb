class CreateRegistrationInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :registration_invitations do |t|
      t.string :email, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :canceled_at
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.references :user, foreign_key: true
      t.timestamps
    end

    add_index :registration_invitations, :token_digest, unique: true
    add_index :registration_invitations, :email, unique: true,
              where: "consumed_at IS NULL AND canceled_at IS NULL",
              name: "index_pending_registration_invitations_on_email"
    add_check_constraint :registration_invitations,
                         "NOT (consumed_at IS NOT NULL AND canceled_at IS NOT NULL)",
                         name: "registration_invitations_single_terminal_state"
    add_check_constraint :registration_invitations,
                         "(consumed_at IS NULL AND user_id IS NULL) OR (consumed_at IS NOT NULL AND user_id IS NOT NULL)",
                         name: "registration_invitations_user_when_consumed"
  end
end
