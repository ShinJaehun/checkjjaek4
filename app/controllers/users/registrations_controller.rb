module Users
  class RegistrationsController < Devise::RegistrationsController
    rate_limit to: 60, within: 1.hour, by: -> { request.remote_ip },
               with: :authentication_rate_limit_exceeded, only: :create

    def new
      return redirect_to(root_path) if user_signed_in?

      @invitation_token = params[:invitation_token].to_s
      @invitation = RegistrationInvitation.find_by_token(@invitation_token)
      return redirect_to(new_user_session_path, alert: t("registration_invitations.errors.invalid")) unless @invitation&.active?

      super
    end

    def create
      return head(:forbidden) if user_signed_in?

      @invitation_token = params[:invitation_token].to_s
      invitation = RegistrationInvitation.find_by_token(@invitation_token)
      return head(:forbidden) unless invitation

      invitation.with_lock do
        return head(:forbidden) unless invitation.active?

        build_resource(sign_up_params.merge(email: invitation.email))
        if resource.terms_accepted == "1"
          resource.terms_accepted_at = Time.current
          resource.terms_version = User::TERMS_VERSION
        end
        resource.save
        if resource.persisted?
          invitation.update!(consumed_at: Time.current, user: resource)
        end
      end

      if resource.persisted?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        @invitation = invitation
        clean_up_passwords resource
        set_minimum_password_length
        respond_with resource
      end
    end

    def destroy
      redirect_to account_withdrawal_path, alert: t("account_withdrawals.errors.use_confirmation"), status: :see_other
    end

    protected

    def build_resource(hash = nil)
      super.tap { |user| user.handle_required_for_registration = true }
    end
  end
end
