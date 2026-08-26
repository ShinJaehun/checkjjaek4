class GroupsController < ApplicationController
  before_action :set_group, only: %i[show edit update close request_reactivation]

  def index
    authorize Group
    @groups = policy_scope(Group).includes(:owner, :group_memberships).order(created_at: :desc)
    @invitations = current_user.group_memberships.invited
      .joins(:group)
      .merge(Group.active)
      .includes(group: :owner)
      .order(created_at: :desc)
  end

  def show
    authorize @group
    @membership = @group.group_memberships.find_by(user: current_user)
    @pending_memberships = if @group.owner?(current_user)
      @group.group_memberships.pending.includes(:user).order(:created_at)
    else
      GroupMembership.none
    end
    @active_memberships = if @group.owner?(current_user)
      @group.group_memberships.active.includes(:user).order(:created_at)
    else
      GroupMembership.none
    end
    @inactive_memberships = if @group.owner?(current_user)
      @group.group_memberships.inactive.includes(:user).order(:created_at)
    else
      GroupMembership.none
    end
    @sent_invitations = if @group.private_group? && @group.owner?(current_user)
      @group.group_memberships.invited.includes(:user).order(:created_at)
    else
      GroupMembership.none
    end
    @invite_candidates = if @group.private_group? && @group.owner?(current_user)
      User.where.not(id: @group.group_memberships.select(:user_id)).order(:name)
    else
      User.none
    end
    prepare_jjaek_context
  end

  def new
    @group = current_user.owned_groups.build
    authorize @group
  end

  def create
    @group = current_user.owned_groups.build(create_group_params)
    authorize @group

    created = Group.transaction do
      next false unless @group.save

      GroupLifecycleEvent.create!(
        group: @group,
        actor: current_user,
        event_type: :opening_requested,
        detail: @group.application_purpose
      )
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

    updated = Group.transaction do
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

  def close
    authorize @group, :close?
    @closure_reason_input = close_group_params[:closure_reason]

    closed = Group.transaction do
      next false unless @group.update(
        lifecycle_status: :inactive,
        closure_reason: @closure_reason_input,
        closed_at: Time.current
      )

      GroupLifecycleEvent.create!(
        group: @group,
        actor: current_user,
        event_type: :operations_closed,
        detail: @closure_reason_input
      )
      true
    end

    if closed
      redirect_to @group, notice: t("groups.notices.closed")
    else
      @group.restore_attributes(%w[lifecycle_status closed_at])
      prepare_lifecycle_history
      render :edit, status: :unprocessable_content
    end
  end

  def request_reactivation
    authorize @group, :request_reactivation?
    Group.transaction do
      @group.pending_approval!
      GroupLifecycleEvent.create!(group: @group, actor: current_user, event_type: :reactivation_requested)
    end

    redirect_to @group, notice: t("groups.notices.reactivation_requested")
  end

  private

  def set_group
    @group = policy_scope(Group).find(params[:id])
  end

  def create_group_params
    params.fetch(:group, {}).permit(:name, :description, :group_type, :application_purpose)
  end

  def update_group_params
    permitted = %i[name description]
    permitted << :application_purpose if @group.pending_approval?
    params.fetch(:group, {}).permit(*permitted)
  end

  def close_group_params
    params.fetch(:group, {}).permit(:closure_reason)
  end

  def prepare_jjaek_context
    group_policy = policy(@group)
    @can_read_group_jjaeks = group_policy.read_jjaeks?
    @jjaeks = if @can_read_group_jjaeks
      policy_scope(@group.jjaeks).includes(:user, :book, :group).recent
    else
      Jjaek.none
    end
    @jjaek = Jjaek.new(user: current_user, group: @group) if group_policy.create_jjaek?
  end

  def prepare_lifecycle_history
    @lifecycle_events = @group.lifecycle_events.includes(:actor)
  end

  def sync_opening_request_detail
    return unless @group.pending_approval? && @group.closed_at.nil?
    return unless @group.saved_change_to_application_purpose?

    @group.lifecycle_events.opening_requested.last&.update!(detail: @group.application_purpose)
  end
end
