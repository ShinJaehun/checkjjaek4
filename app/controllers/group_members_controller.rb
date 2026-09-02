class GroupMembersController < ApplicationController
  def index
    @group = policy_scope(Group).find(params[:group_id])
    authorize @group, :view_members?

    @active_memberships = @group.group_memberships.active.includes(:user).order(:created_at)
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
    @group_member_bans = @group.group_member_bans.includes(:user).order(created_at: :desc)
    @ban_actions_by_id = ban_actions_by_id
    @can_invite = policy(@group.group_memberships.build(user: User.new, status: :invited)).invite?
    @invite_candidates = invite_candidates
    @admin_transfer_candidates = admin_transfer_candidates
    @current_activity_suspensions_by_membership_id = current_activity_suspensions_by_membership_id
    @membership_history = membership_history
  end

  private

  def invite_candidates
    return User.none unless @can_invite

    User.active_accounts
      .where.not(id: @group.group_memberships.select(:user_id))
      .where.not(id: @group.group_member_bans.select(:user_id))
      .order(:name)
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

  def current_activity_suspensions_by_membership_id
    membership_ids = @active_memberships.select(&:activity_suspended?).map(&:id)
    return {} if membership_ids.empty?

    restored_action_ids = ModerationAction
      .where(target_type: "GroupMembership", target_id: membership_ids, action_type: :restore_activity)
      .where.not(reversal_of_id: nil)
      .select(:reversal_of_id)

    ModerationAction.where(target_type: "GroupMembership", target_id: membership_ids)
      .where(action_type: :suspend_activity)
      .where.not(id: restored_action_ids)
      .order(created_at: :desc, id: :desc)
      .group_by(&:target_id)
      .transform_values(&:first)
  end

  def membership_history
    lifecycle_events = @group.group_membership_events.includes(:user, :actor).to_a
    moderation_actions = ModerationAction.for_membership_group(@group)
      .where(action_type: %i[suspend_activity restore_activity ban_from_group unban_from_group])
      .includes(:actor)
      .to_a
    users_by_id = User.where(id: moderation_actions.map(&:membership_user_id).compact.uniq).index_by(&:id)

    entries = lifecycle_events.map { |event| { source: :lifecycle, record: event, user: event.user } }
    entries.concat(
      moderation_actions.filter_map do |action|
        user = users_by_id[action.membership_user_id]
        { source: :moderation, record: action, user: } if user
      end
    )

    source_order = { lifecycle: 0, moderation: 1 }
    entries.sort_by { |entry| [ entry[:record].created_at, source_order.fetch(entry[:source]), entry[:record].id ] }.reverse
  end

  def ban_actions_by_id
    ModerationAction.where(
      target_type: "GroupMemberBan",
      target_id: @group_member_bans.reselect(:id).reorder(nil),
      action_type: :ban_from_group
    )
      .includes(:actor)
      .order(created_at: :desc, id: :desc)
      .group_by(&:target_id)
      .transform_values(&:first)
  end
end
