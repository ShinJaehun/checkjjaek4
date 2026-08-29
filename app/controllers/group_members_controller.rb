class GroupMembersController < ApplicationController
  def index
    @group = policy_scope(Group).find(params[:group_id])
    authorize @group, :view_members?

    @active_memberships = @group.group_memberships.active.includes(:user).order(:created_at)
    @inactive_memberships = @group.group_memberships.inactive.includes(:user).order(:created_at)
    @pending_memberships = if @group.approval_group?
      @group.group_memberships.pending.includes(:user).order(:created_at)
    else
      GroupMembership.none
    end
    @sent_invitations = if @group.private_group?
      @group.group_memberships.invited.includes(:user).order(:created_at)
    else
      GroupMembership.none
    end
    @can_invite = policy(@group.group_memberships.build(user: User.new, status: :invited)).invite?
    @invite_candidates = invite_candidates
    @admin_transfer_candidates = admin_transfer_candidates
    @activity_moderation_actions_by_membership_id = activity_moderation_actions_by_membership_id
  end

  private

  def invite_candidates
    return User.none unless @can_invite

    User.active_accounts.where.not(id: @group.group_memberships.select(:user_id)).order(:name)
  end

  def admin_transfer_candidates
    return User.none unless policy(@group).transfer_admin?

    @group.active_group_memberships
      .moderation_status_normal
      .where.not(user_id: @group.group_admin_id)
      .includes(:user)
      .map(&:user)
      .sort_by(&:name)
  end

  def activity_moderation_actions_by_membership_id
    membership_ids = @active_memberships.ids + @inactive_memberships.ids

    ModerationAction.where(target_type: "GroupMembership", target_id: membership_ids)
      .includes(:actor, :reversal_of)
      .order(:created_at, :id)
      .group_by(&:target_id)
  end
end
