module Jjaeks
  class GroupHidesController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      Jjaeks::Hide.new(@jjaek, actor: current_user, **action_params).call!

      redirect_to jjaek_path(@jjaek), notice: t("jjaeks.moderation.notices.hidden")
    rescue Jjaeks::Hide::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @jjaek.reload
      @error_message = t("jjaeks.moderation.alerts.hide_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @jjaek = Jjaek.find(params[:jjaek_id])
      authorize @jjaek, :hide_as_group_admin?
      @moderation_action = ModerationAction.new
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
