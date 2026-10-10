require "openssl"

module Users
  class SessionsController < Devise::SessionsController
    rate_limit to: 120, within: 5.minutes, by: -> { request.remote_ip },
               name: "login-ip", with: :authentication_rate_limit_exceeded, only: :create
    rate_limit to: 8, within: 5.minutes, by: :login_ip_and_email_key,
               name: "login-ip-email", with: :authentication_rate_limit_exceeded, only: :create

    skip_before_action :reject_suspended_session!, only: :create

    def create
      suspended_user = authenticated_suspended_user
      return super unless suspended_user

      self.resource = suspended_user
      reason = suspended_user.current_suspension_action&.public_reason
      reason = User.suspension_reason_label(reason) if reason.present?
      request.env["devise.allow_params_authentication"] = false
      flash.now[:alert] = reason.present? ? t("auth.alerts.suspended", reason:) : t("auth.alerts.suspended_fallback")
      render :new, status: :unprocessable_content
    end

    private

    def login_ip_and_email_key
      email = sign_in_params[:email].to_s.strip.downcase
      secret = Rails.application.key_generator.generate_key("login-rate-limit-email", 32)
      email_digest = OpenSSL::HMAC.hexdigest("SHA256", secret, email)
      "#{request.remote_ip}:#{email_digest}"
    end

    def authenticated_suspended_user
      user = resource_class.find_for_database_authentication(email: sign_in_params[:email])
      user if user&.suspended? && !user.withdrawn? && user.valid_password?(sign_in_params[:password])
    end
  end
end
