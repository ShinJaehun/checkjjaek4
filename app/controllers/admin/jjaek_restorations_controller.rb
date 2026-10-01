module Admin
  class JjaekRestorationsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      Jjaeks::Restore.new(@jjaek, actor: current_user, **action_params).call!

      redirect_to jjaek_path(@jjaek), notice: t("admin.jjaeks.notices.restored")
    rescue Jjaeks::Restore::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @jjaek.reload
      @current_hide_action = @jjaek.current_hide_action
      @error_message = t("admin.jjaeks.alerts.restore_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @jjaek = Jjaek.find_by(id: params[:jjaek_id])
      unless @jjaek && policy(@jjaek).show?
        redirect_to root_path, alert: t("jjaeks.alerts.not_found_or_inaccessible")
        return
      end

      authorize @jjaek, :restore?
      @current_hide_action = @jjaek.current_hide_action
      @moderation_action = ModerationAction.new
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
