module GroupMemberships
  class MemberBansController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      GroupMemberBans::Ban.new(
        @membership,
        actor: current_user,
        **action_params
      ).call!

      redirect_to group_members_path(@group), notice: t("group_member_bans.notices.banned")
    rescue GroupMemberBans::Ban::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @membership.reload
      @error_message = t("group_member_bans.alerts.ban_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, :view_members?
      @membership = @group.group_memberships.includes(:user).find(params[:group_membership_id])
      authorize @membership, :ban_from_group?
      @moderation_action = ModerationAction.new
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
