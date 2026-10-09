class GroupsController < ApplicationController
  before_action :set_group, only: %i[show edit update]

  def index
    authorize Group
    @groups = policy_scope(Group, policy_scope_class: GroupPolicy::MembershipScope)
      .includes(:group_admin, :group_memberships)
      .order(created_at: :desc, id: :desc)
    @group_activity_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::GroupActivityScope)
      .includes(:user, :book, :target_user, :likes, :comments, :group, :moderation_actions,
                quoted_jjaek: [ :user, :book, :group ])
      .order(created_at: :desc, id: :desc)
    prepare_visible_requote_counts_for(@group_activity_jjaeks)
    @invitations = current_user.group_memberships.invited
      .joins(:group)
      .merge(Group.active)
      .includes(group: :group_admin)
      .order(created_at: :desc)
  end

  def show
    authorize @group
    active_member_scope = @group.active_group_memberships.where.not(user_id: @group.group_admin_id)
    @member_preview = active_member_scope.includes(:user).order(:created_at, :id).limit(5).map(&:user)
    @active_member_count = active_member_scope.count
    @membership = @group.group_memberships.find_by(user: current_user)
    @group_member_ban = @group.group_member_bans.find_by(user: current_user)
    @current_group_ban_action = @group_member_ban&.current_ban_action
    @current_operation_suspension = @group.current_operation_suspension_action
    @current_activity_suspension = @membership&.current_activity_suspension_action if @membership&.activity_suspended?
    prepare_jjaek_context
  end

  def new
    @group = current_user.administered_groups.build
    authorize @group
  end

  def create
    @group = current_user.administered_groups.build(create_group_params)
    @group.lifecycle_status = :active if current_user.global_admin?
    authorize @group

    created = Group.transaction do
      next false unless @group.save

      event = GroupLifecycleEvent.create!(
        group: @group,
        actor: current_user,
        event_type: current_user.global_admin? ? :opening_approved : :opening_requested,
        detail: @group.application_purpose
      )
      recipient_ids = if event.opening_requested?
        eligible_global_admin_ids
      else
        [ @group.group_admin_id ]
      end
      Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids:)
      true
    end

    if created
      redirect_to @group, notice: t("groups.notices.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @group
    prepare_lifecycle_history
  end

  def update
    authorize @group

    updated = @group.with_lock do
      authorize @group
      next false unless @group.update(update_group_params)

      sync_opening_request_detail
      true
    end

    if updated
      redirect_to @group, notice: t("groups.notices.updated")
    else
      prepare_lifecycle_history
      render :edit, status: :unprocessable_content
    end
  end

  private

  def eligible_global_admin_ids
    User.where(global_admin: true, withdrawn_at: nil, suspended_at: nil).pluck(:id)
  end

  def set_group
    @group = policy_scope(Group).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    raise unless action_name == "show"

    ban = GroupMemberBan.find_by(group_id: params[:id], user: current_user)
    if ban
      reason = ban.current_ban_action&.public_reason
      redirect_to groups_path, alert: t("group_member_bans.alerts.access_restricted", reason:)
      return
    end

    if GroupMembershipRemoval.exists?(group_id: params[:id], user: current_user)
      redirect_to groups_path, alert: t("group_memberships.alerts.removed")
      return
    end

    redirect_to groups_path, alert: t("groups.alerts.not_found_or_inaccessible")
  end

  def create_group_params
    params.fetch(:group, {}).permit(:name, :description, :group_type, :application_purpose)
  end

  def update_group_params
    permitted = %i[name description]
    permitted << :application_purpose if @group.pending_approval?
    params.fetch(:group, {}).permit(*permitted)
  end

  def prepare_jjaek_context
    group_policy = policy(@group)
    @can_read_group_jjaeks = group_policy.read_jjaeks?
    @jjaeks = if @can_read_group_jjaeks
      policy_scope(
        @group.jjaeks,
        policy_scope_class: JjaekPolicy::GroupContentScope
      ).includes(:user, :book, :group, :moderation_actions, quoted_jjaek: [ :user, :book, :group ]).recent
    else
      Jjaek.none
    end
    prepare_visible_requote_counts_for(@jjaeks)
    @jjaek = Jjaek.new(user: current_user, group: @group) if group_policy.create_jjaek?
  end

  def prepare_lifecycle_history
    @lifecycle_events = @group.lifecycle_events.includes(:actor).to_a
    @operation_moderation_actions = ModerationAction
      .where(target: @group, action_type: %i[suspend_group_operation restore_group_operation])
      .includes(:actor)
      .order(:created_at, :id)
      .to_a
  end

  def sync_opening_request_detail
    return unless @group.pending_approval? && @group.closed_at.nil?
    return unless @group.saved_change_to_application_purpose?

    @group.lifecycle_events.opening_requested.last&.update!(detail: @group.application_purpose)
  end
end
