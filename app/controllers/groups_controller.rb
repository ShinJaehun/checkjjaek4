class GroupsController < ApplicationController
  include GroupShowContext

  before_action :prepare_feed_response_format, only: %i[index show]
  before_action :set_group, only: %i[show edit update]
  before_action :prepare_group_creation, only: :create
  rate_limit to: 5, within: 24.hours, by: -> { current_user.id },
             with: :group_creation_rate_limit_exceeded, only: :create

  def index
    authorize Group
    @group_activity_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::GroupActivityScope)
      .includes(:book, :likes, :comments, :group, :moderation_actions,
                user: { avatar_attachment: :blob }, target_user: { avatar_attachment: :blob }, quoted_jjaek: [ { user: { avatar_attachment: :blob } }, :book, :group ])
      .order(created_at: :desc, id: :desc)
    @feed_page = FeedPage.new(jjaeks: @group_activity_jjaeks, cursor: params[:cursor])
    @feed_next_url = groups_path(cursor: @feed_page.next_cursor) if @feed_page.next_cursor
    @group_activity_jjaeks = @feed_page.items
    prepare_current_reading_states_for(@group_activity_jjaeks)
    prepare_visible_requote_counts_for(@group_activity_jjaeks)
    return render_feed_page(context: :group, next_url: @feed_next_url) if feed_page_request?

    hidden_group_ids = current_user.group_list_hidings.select(:group_id)
    groups = policy_scope(Group, policy_scope_class: GroupPolicy::MembershipScope).where.not(id: hidden_group_ids)
    memberships = GroupMembership.displayed_for(user: current_user, groups:)
      .preload(group: { group_admin: { avatar_attachment: :blob } }).to_a
    @groups = memberships.map(&:group)
    @memberships_by_group_id = memberships.index_by(&:group_id)
    prepare_group_card_members
    managed_approval_group_ids = @groups.select { |group| group.approval_group? && group.group_admin?(current_user) }.map(&:id)
    @pending_membership_counts = GroupMembership.pending.where(group_id: managed_approval_group_ids)
      .group(:group_id).count
    past_group_scope = policy_scope(Group, policy_scope_class: GroupPolicy::PastMembershipScope)
      .where.not(id: hidden_group_ids)
    @past_group_states = {}
    if past_group_scope.exists?
      past_groups = past_group_scope
        .select(:id, :name, :group_type, :lifecycle_status, :operation_suspended_at, :closed_at).index_by(&:id)
      @past_group_states = GroupMembershipEvent.past_states_for(user: current_user, groups: past_groups.values)
      @groups.concat(@past_group_states.keys.map { |id| past_groups.fetch(id) })
    end
    @can_manage_group_list = @groups.size >= 2 || @past_group_states.any? || current_user.group_list_hidings.exists? ||
      memberships.any?(&:removable_from_list?)
    @invitations = current_user.group_memberships.invited
      .joins(:group)
      .merge(Group.active)
      .includes(group: :group_admin)
      .order(created_at: :desc)
  end

  def show
    if policy(@group).cleanup_content?
      authorize @group, :cleanup_content?
      return prepare_restricted_content
    end
    authorize @group
    if feed_page_request?
      prepare_group_jjaek_context
      return render_feed_page(context: :group, next_url: @feed_next_url)
    end
    prepare_group_show_context
    prepare_lifecycle_history if @group.application_ended?
    @jjaek = Jjaek.new(user: current_user, group: @group) if policy(@group).create_jjaek?
  end

  def new
    @group = current_user.administered_groups.build
    authorize @group
    prepare_application_context
  end

  def create
    created = current_user.with_lock do
      @group.lifecycle_status = current_user.global_admin? ? :active : :pending_approval
      authorize @group
      prepare_application_context
      if @pending_opening_application
        @group.errors.add(:base, t("groups.applications.limit_reached"))
        next false
      end
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
  rescue ActiveRecord::RecordInvalid
    @group.errors.add(:base, t("groups.alerts.application_failed"))
    render :new, status: :unprocessable_content
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

  def prepare_restricted_content
    @content_section = params[:content] == "comments" ? "comments" : "jjaeks"
    scope = if @content_section == "comments"
      policy_scope(Comment, policy_scope_class: CommentPolicy::GroupCleanupScope)
        .where(jjaeks: { group_id: @group.id })
        .select("comments.*, jjaeks.hidden_at AS parent_hidden_at")
    else
      policy_scope(Jjaek, policy_scope_class: JjaekPolicy::GroupCleanupScope).where(group_id: @group.id)
    end
    @content_page = Admin::InventoryPage.new(scope.order(created_at: :desc, id: :desc), page: params[:page])
    render "groups/restricted_content/show", formats: :html
  end

  def prepare_group_card_members
    @active_member_counts_by_group_id = {}
    @member_previews_by_group_id = {}
    return if @groups.empty?

    ranked_memberships = GroupMembership.active.joins(:group)
      .where(group_id: @groups.map(&:id))
      .where("group_memberships.user_id <> groups.group_admin_id")
      .select(<<~SQL.squish)
        group_memberships.*,
        COUNT(*) OVER (PARTITION BY group_memberships.group_id) AS active_member_count,
        ROW_NUMBER() OVER (
          PARTITION BY group_memberships.group_id
          ORDER BY group_memberships.created_at, group_memberships.id
        ) AS member_preview_rank
      SQL

    GroupMembership.from(ranked_memberships, :group_memberships)
      .where("member_preview_rank <= ?", 3)
      .order(:group_id, :created_at, :id)
      .preload(user: { avatar_attachment: :blob })
      .each do |membership|
        @active_member_counts_by_group_id[membership.group_id] = membership[:active_member_count].to_i
        (@member_previews_by_group_id[membership.group_id] ||= []) << membership.user
      end
  end

  def prepare_group_creation
    @group = current_user.administered_groups.build(create_group_params)
    @group.lifecycle_status = :active if current_user.global_admin?
    authorize @group
  end

  def prepare_application_context
    @pending_opening_application = current_user.administered_groups.pending_opening_applications.first unless current_user.global_admin?
    @past_applications = current_user.administered_groups.ended_applications.order(created_at: :desc, id: :desc).limit(10)
  end

  def group_creation_rate_limit_exceeded
    message = t("groups.alerts.rate_limited")
    respond_to do |format|
      format.turbo_stream { render_content_rate_limit_flash(message) }
      format.html do
        flash.now[:alert] = message
        render :new, status: :too_many_requests
      end
    end
  end

  def eligible_global_admin_ids
    User.where(global_admin: true, withdrawn_at: nil, suspended_at: nil).pluck(:id)
  end

  def set_group
    # Group#to_param includes its current name. Historical access only needs the numeric ID.
    group_id = params[:id].to_s.split("-", 2).first
    if action_name == "show"
      @group = policy_scope(Group, policy_scope_class: GroupPolicy::PastMembershipScope).find_by(id: group_id)
    end
    @group ||= policy_scope(Group).find(params[:id])
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
