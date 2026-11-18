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
      return render_invalid_invitation unless invitation

      invitation.with_lock do
        return render_invalid_invitation unless invitation.active? && invitation.matches_token?(@invitation_token)

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

    def update_resource(resource, params)
      resource.with_lock do
        raise Pundit::NotAuthorizedError unless resource.active_account? && !resource.suspended?

        super
      end
    end

    def build_resource(hash = nil)
      super.tap { |user| user.handle_required_for_registration = true }
    end

    private

    def render_invalid_invitation
      @invitation = nil
      @invitation_error = t("registration_invitations.errors.unusable")
      render :new, formats: :html, status: :forbidden
    end

    def authentication_rate_limit_exceeded
      @invitation_token = params[:invitation_token].to_s
      @invitation = RegistrationInvitation.find_by_token(@invitation_token)
      @invitation = nil unless @invitation&.active?

      attributes = if @invitation
        sign_up_params.slice(:name, :handle, :terms_accepted).merge(email: @invitation.email)
      else
        {}
      end
      build_resource(attributes)
      clean_up_passwords resource
      @password_reentry_required = @invitation.present?
      request.env["devise.allow_params_authentication"] = false
      flash.now[:alert] = authentication_rate_limit_message
      render :new, formats: :html, status: :too_many_requests
    end
  end
end
