module Admin
  class UserAccountSuspensionsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      Users::SuspendAccount.new(@user, actor: current_user, **action_params).call!

      redirect_to admin_user_path(@user), notice: t("admin.users.notices.suspended")
    rescue Users::SuspendAccount::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @user.reload
      @error_message = t("admin.users.alerts.suspend_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @user = User.find(params[:user_id])
      authorize @user, :suspend?
      @has_administered_groups = @user.administered_groups.exists?
      @moderation_action = ModerationAction.new
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
