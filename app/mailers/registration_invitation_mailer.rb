class RegistrationInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @registration_url = new_user_registration_url(invitation_token: token)
    @expires_at = invitation.expires_at
    mail(to: invitation.email, subject: I18n.t("registration_invitations.mail.subject"))
  end
end
