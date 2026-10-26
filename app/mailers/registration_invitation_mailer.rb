class RegistrationInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @registration_url = new_user_registration_url(invitation_token: token)
    @expires_at_text = I18n.l(invitation.expires_at.in_time_zone, locale: :ko, format: :long)
    attachments.inline["bookjjaek-logo.png"] = File.binread(Rails.root.join("app/assets/images/logo/logo_black_mini.png"))
    mail(to: invitation.email, subject: I18n.t("registration_invitations.mail.subject"))
  end
end
