require "openssl"

module Users
  class PasswordsController < Devise::PasswordsController
    rate_limit to: 60, within: 1.hour, by: -> { request.remote_ip },
               name: "password-reset-ip", with: :password_reset_rate_limit_exceeded, only: :create
    rate_limit to: 3, within: 1.hour, by: :reset_ip_and_email_key,
               name: "password-reset-ip-email", with: :password_reset_rate_limit_exceeded, only: :create

    def create
      email = normalized_email
      resource_class.active_accounts.find_by(email:)&.send_reset_password_instructions
      redirect_to new_user_password_path, notice: t("auth.passwords.request_sent")
    end

    private

    def normalized_email
      user_params = params[:user]
      user_params.is_a?(ActionController::Parameters) ? user_params[:email].to_s.strip.downcase : ""
    end

    def reset_ip_and_email_key
      secret = Rails.application.key_generator.generate_key("password-reset-rate-limit-email", 32)
      email_digest = OpenSSL::HMAC.hexdigest("SHA256", secret, normalized_email)
      "#{request.remote_ip}:#{email_digest}"
    end

    def password_reset_rate_limit_exceeded
      self.resource = resource_class.new
      flash.now[:alert] = t("auth.passwords.rate_limited")
      render :new, formats: :html, status: :too_many_requests
    end
  end
end
