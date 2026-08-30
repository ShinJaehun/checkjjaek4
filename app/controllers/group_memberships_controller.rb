class GroupMembershipsController < ApplicationController
  before_action :set_group, except: %i[accept decline]
  before_action :authorize_group_access, only: %i[update destroy reject revoke remove suspend_activity restore_activity]
  before_action :set_membership, only: %i[update destroy reject revoke remove suspend_activity restore_activity]
  before_action :set_own_invitation, only: %i[accept decline]

  def create
    @membership = @group.group_memberships.build(
      user: current_user,
      status: @group.public_group? ? :active : :pending
    )
    authorize @membership

    if @membership.save
      notice = @membership.active? ? t("group_memberships.notices.joined") : t("group_memberships.notices.requested")
      redirect_to @group, notice: notice
    else
      redirect_to @group, alert: @membership.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @membership, :approve?
    @membership.active!

    redirect_to group_members_path(@group), notice: t("group_memberships.notices.approved")
  end

  def invite
    @membership = @group.group_memberships.build(user_id: params[:user_id], status: :invited)
    authorize @membership, :invite?

    if @membership.save
      redirect_to group_members_path(@group), notice: t("group_memberships.notices.invited")
    else
      redirect_to group_members_path(@group), alert: @membership.errors.full_messages.to_sentence
    end
  end

  def accept
    authorize @membership, :accept?
    @membership.active!

    redirect_to @membership.group, notice: t("group_memberships.notices.accepted")
  end

  def decline
    authorize @membership, :decline?
    @membership.destroy!

    redirect_to groups_path, notice: t("group_memberships.notices.declined"), status: :see_other
  end

  def reject
    authorize @membership, :reject?
    @membership.destroy!

    redirect_to group_members_path(@group), notice: t("group_memberships.notices.rejected"), status: :see_other
  end

  def revoke
    authorize @membership, :revoke?
    @membership.destroy!

    redirect_to group_members_path(@group), notice: t("group_memberships.notices.revoked"), status: :see_other
  end

  def remove
    authorize @membership, :remove?
    GroupMembership.transaction do
      removal = GroupMembershipRemoval.find_or_initialize_by(group: @group, user: @membership.user)
      removal.removed_by = current_user
      removal.save!
      @membership.destroy!
    end

    redirect_to group_members_path(@group), notice: t("group_memberships.notices.removed"), status: :see_other
  end

  def suspend_activity
    authorize @membership, :suspend_activity?
    GroupMemberships::SuspendActivity.new(
      @membership,
      actor: current_user,
      **moderation_action_params
    ).call!

    redirect_to group_members_path(@group), notice: t("group_memberships.notices.activity_suspended")
  rescue GroupMemberships::SuspendActivity::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to group_members_path(@group), alert: t("group_memberships.alerts.suspend_activity_failed")
  end

  def restore_activity
    authorize @membership, :restore_activity?
    GroupMemberships::RestoreActivity.new(
      @membership,
      actor: current_user,
      **moderation_action_params
    ).call!

    redirect_to group_members_path(@group), notice: t("group_memberships.notices.activity_restored")
  rescue GroupMemberships::RestoreActivity::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to group_members_path(@group), alert: t("group_memberships.alerts.restore_activity_failed")
  end

  def destroy
    authorize @membership
    pending = @membership.pending?
    @membership.destroy!

    redirect_to groups_path,
                notice: t(pending ? "group_memberships.notices.cancelled" : "group_memberships.notices.left"),
                status: :see_other
  end

  private

  def set_group
    @group = policy_scope(Group).find(params[:group_id])
  end

  def set_membership
    @membership = @group.group_memberships.find(params[:id])
  end

  def set_own_invitation
    @membership = current_user.group_memberships.invited.find_by!(id: params[:id], group_id: params[:group_id])
  end

  def authorize_group_access
    authorize @group, :show?
  end

  def moderation_action_params
    params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
  end
end
