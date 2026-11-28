require "net/smtp"
require "openssl"

module Admin
  class RegistrationInvitationsController < ApplicationController
    def index
      authorize RegistrationInvitation
      @invitation = RegistrationInvitation.new
      load_invitations
    end

    def create
      authorize RegistrationInvitation
      @invitation = RegistrationInvitation.new(email: invitation_params[:email], invited_by: current_user)
      token = @invitation.issue_token!

      if @invitation.save
        deliver_invitation(@invitation, token, notice: "registration_invitations.notices.sent")
      else
        load_invitations
        render :index, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotUnique
      redirect_to admin_registration_invitations_path, alert: t("registration_invitations.errors.duplicate")
    end

    def resend
      invitation = RegistrationInvitation.find(params[:id])
      authorize invitation
      token = invitation.with_lock { invitation.resend_token! }
      deliver_invitation(invitation, token, notice: "registration_invitations.notices.resent")
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_registration_invitations_path, alert: t("registration_invitations.errors.cannot_resend")
    end

    def destroy
      invitation = RegistrationInvitation.find(params[:id])
      authorize invitation
      invitation.with_lock { invitation.cancel! }
      redirect_to admin_registration_invitations_path, notice: t("registration_invitations.notices.canceled"), status: :see_other
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_registration_invitations_path, alert: t("registration_invitations.errors.cannot_cancel"), status: :see_other
    end

    private

    def deliver_invitation(invitation, token, notice:)
      RegistrationInvitationMailer.invite(invitation, token).deliver_now
      redirect_to admin_registration_invitations_path, notice: t(notice)
    rescue Net::SMTPError, Net::ProtocolError, SocketError, SystemCallError,
           IOError, Timeout::Error, OpenSSL::SSL::SSLError => error
      Rails.logger.warn("Registration invitation email delivery failed invitation_id=#{invitation.id} error=#{error.class}")
      redirect_to admin_registration_invitations_path, alert: t("registration_invitations.errors.delivery_failed"), status: :see_other
    end

    def load_invitations
      @invitation_page = InventoryPage.new(policy_scope(RegistrationInvitation).recent_first, page: params[:page])
      @invitations = @invitation_page.records
    end

    def invitation_params
      params.require(:registration_invitation).permit(:email)
    end
  end
end
