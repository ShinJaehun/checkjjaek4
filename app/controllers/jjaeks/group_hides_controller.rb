module Jjaeks
  class GroupHidesController < ApplicationController
    include GroupContentReturnContext

    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      Jjaeks::Hide.new(@jjaek, actor: current_user, **action_params).call!

      redirect_to @return_path, notice: t("jjaeks.moderation.notices.hidden")
    rescue Jjaeks::Hide::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @jjaek.reload
      @error_message = t("jjaeks.moderation.alerts.hide_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @jjaek = Jjaek.find_by(id: params[:jjaek_id])
      unless @jjaek && policy(@jjaek).show?
        redirect_to root_path, alert: t("jjaeks.alerts.not_found_or_inaccessible")
        return
      end

      authorize @jjaek, :hide_as_group_admin?
      @moderation_action = ModerationAction.new
      prepare_group_content_return(default_path: jjaek_path(@jjaek))
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
