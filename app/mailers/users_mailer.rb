class UsersMailer < Devise::Mailer
  default reply_to: "support@jjaek.kr", template_path: "devise/mailer"
  layout "mailer"

  def reset_password_instructions(record, token, opts = {})
    attachments.inline["bookjjaek-logo.png"] = File.binread(Rails.root.join("app/assets/images/logo/logo_black_mini.png"))
    super
  end
end
