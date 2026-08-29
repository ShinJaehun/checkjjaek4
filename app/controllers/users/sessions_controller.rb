module Users
  class SessionsController < Devise::SessionsController
    skip_before_action :reject_suspended_session!, only: :create

    def create
      suspended_user = authenticated_suspended_user
      return super unless suspended_user

      self.resource = suspended_user
      reason = suspended_user.current_suspension_action&.public_reason
      flash.now[:alert] = reason.present? ? t("auth.alerts.suspended", reason:) : t("auth.alerts.suspended_fallback")
      render :new, status: :unprocessable_content
    end

    private

    def authenticated_suspended_user
      user = resource_class.find_for_database_authentication(email: sign_in_params[:email])
      user if user&.suspended? && !user.withdrawn? && user.valid_password?(sign_in_params[:password])
    end
  end
end
