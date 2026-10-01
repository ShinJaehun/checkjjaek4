module GroupMemberships
  class ActivityRestorationsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      RestoreActivity.new(@membership, actor: current_user, **action_params).call!
      redirect_to group_members_path(@group), notice: t("group_memberships.notices.activity_restored")
    rescue RestoreActivity::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @membership.reload
      @error_message = t("group_memberships.alerts.restore_activity_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, :show?
      @membership = @group.group_memberships.includes(:user).find_by(id: params[:group_membership_id])
      unless @membership
        redirect_to group_members_path(@group), alert: t("group_memberships.alerts.stale_action")
        return
      end

      authorize @membership, :restore_activity?
      @current_activity_suspension = @membership.current_activity_suspension_action
      @moderation_action = ModerationAction.new
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
