class GroupMemberBansController < ApplicationController
  before_action :set_group

  def create
    membership = @group.group_memberships.find(params[:membership_id])
    authorize membership, :ban_from_group?
    GroupMemberBans::Ban.new(
      membership,
      actor: current_user,
      **moderation_action_params
    ).call!

    redirect_to group_members_path(@group), notice: t("group_member_bans.notices.created"), status: :see_other
  rescue GroupMemberBans::Ban::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to group_members_path(@group), alert: t("group_member_bans.alerts.create_failed"), status: :see_other
  end

  def destroy
    ban = @group.group_member_bans.find(params[:id])
    authorize ban
    GroupMemberBans::Unban.new(
      ban,
      actor: current_user,
      **moderation_action_params
    ).call!

    redirect_to group_members_path(@group), notice: t("group_member_bans.notices.destroyed"), status: :see_other
  rescue GroupMemberBans::Unban::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to group_members_path(@group), alert: t("group_member_bans.alerts.destroy_failed"), status: :see_other
  end

  private

  def set_group
    @group = policy_scope(Group).find(params[:group_id])
    authorize @group, :view_members?
  end

  def moderation_action_params
    params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
  end
end
