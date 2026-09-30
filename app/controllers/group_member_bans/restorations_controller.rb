module GroupMemberBans
  class RestorationsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      Unban.new(
        @ban,
        actor: current_user,
        **action_params
      ).call!

      redirect_to group_members_path(@group), notice: t("group_member_bans.notices.unbanned")
    rescue Unban::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @ban.reload
      @error_message = t("group_member_bans.alerts.unban_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, :view_members?
      @ban = @group.group_member_bans.includes(:user).find_by(id: params[:group_member_ban_id])
      unless @ban
        redirect_to group_members_path(@group), alert: t("group_member_bans.alerts.stale_restoration")
        return
      end

      authorize @ban, :unban?
      @current_ban_action = @ban.current_ban_action
      @moderation_action = ModerationAction.new
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
