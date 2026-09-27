module GroupMemberships
  class ActivitySuspensionsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      SuspendActivity.new(@membership, actor: current_user, **action_params).call!
      redirect_to group_members_path(@group), notice: t("group_memberships.notices.activity_suspended")
    rescue SuspendActivity::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @membership.reload
      @error_message = t("group_memberships.alerts.suspend_activity_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, :show?
      @membership = @group.group_memberships.includes(:user).find(params[:group_membership_id])
      authorize @membership, :suspend_activity?
      @moderation_action = ModerationAction.new
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
