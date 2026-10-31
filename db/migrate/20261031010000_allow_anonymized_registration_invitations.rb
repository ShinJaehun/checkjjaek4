class AllowAnonymizedRegistrationInvitations < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :registration_invitations, name: "registration_invitations_user_when_consumed"
    add_check_constraint :registration_invitations,
                         "(consumed_at IS NULL AND user_id IS NULL) OR " \
                         "(consumed_at IS NOT NULL AND (user_id IS NOT NULL OR " \
                         "email = ('withdrawn-invitation-' || id::text || '@users.invalid')))",
                         name: "registration_invitations_user_when_consumed"
  end

  def down
    remove_check_constraint :registration_invitations, name: "registration_invitations_user_when_consumed"
    add_check_constraint :registration_invitations,
                         "(consumed_at IS NULL AND user_id IS NULL) OR (consumed_at IS NOT NULL AND user_id IS NOT NULL)",
                         name: "registration_invitations_user_when_consumed"
  end
end
