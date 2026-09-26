module Admin
  class GroupsController < ApplicationController
    def index
      authorize Group, :view_admin_inventory?
      groups = policy_scope(Group, policy_scope_class: GroupPolicy::AdminInventoryScope)
      scope = GroupInventoryQuery.new(groups, params).call.includes(:group_admin)
      @inventory_page = InventoryPage.new(scope, page: params[:page])
      @groups = @inventory_page.records
      @latest_activities_by_group_id = LatestContentActivityQuery.new(
        owner_type: :group,
        owner_ids: @groups.map(&:id)
      ).call
    end

    def show
      @group = Group.find(params[:id])
      authorize @group, :view_admin_details?
      @lifecycle_events = @group.lifecycle_events.includes(:actor)
      @current_operation_suspension = @group.current_operation_suspension_action
      @operation_moderation_actions = ModerationAction
        .where(target: @group, action_type: %i[suspend_group_operation restore_group_operation])
        .includes(:actor)
        .order(:created_at, :id)
        .to_a
      @can_suspend_operation = policy(@group).suspend_operation?
      @can_restore_operation = policy(@group).restore_operation?
      @membership_counts = @group.group_memberships.group(:status).count
      @return_params = params.permit(:q, :group_type, :status, :operation_status, :sort, :page)
    end

    def content
      @group = Group.find(params[:id])
      authorize @group, :view_admin_details?
      @content_section = permitted_content_section
      @content_filter_params = params.permit(:content_q, :content_status, :content_sort)
      @return_params = params.permit(:q, :group_type, :status, :operation_status, :sort, :page)

      jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::AdminInventoryScope)
        .where(group: @group)

      comments = policy_scope(Comment, policy_scope_class: CommentPolicy::AdminInventoryScope)
        .joins(:jjaek)
        .where(jjaeks: { group_id: @group.id })

      @timeline_page = GroupContentTimelineQuery.new(
        jjaek_scope: jjaeks,
        comment_scope: comments,
        content_section: @content_section,
        params:
      ).call
      @timeline_items = @timeline_page.records
    end

    def approve
      @group = Group.find(params[:id])
      authorize @group, :approve?
      event_type = @group.closed_at.nil? ? :opening_approved : :reactivation_approved

      Group.transaction do
        recipient_ids = if event_type == :reactivation_approved
          @group.group_memberships.active.distinct.pluck(:user_id)
        else
          [ @group.group_admin_id ]
        end
        @group.active!
        event = GroupLifecycleEvent.create!(group: @group, actor: current_user, event_type: event_type)
        Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids:)
        event
      end

      redirect_to admin_groups_path, notice: t("admin.groups.notices.approved")
    end

    def suspend_operation
      @group = Group.find(params[:id])
      authorize @group, :suspend_operation?
      Groups::SuspendOperation.new(@group, actor: current_user, **moderation_action_params).call!
      redirect_to admin_group_path(@group), notice: t("admin.groups.notices.operation_suspended")
    rescue Groups::SuspendOperation::Error, ActiveRecord::RecordInvalid
      redirect_to admin_group_path(@group), alert: t("admin.groups.alerts.operation_suspend_failed")
    end

    def restore_operation
      @group = Group.find(params[:id])
      authorize @group, :restore_operation?
      Groups::RestoreOperation.new(@group, actor: current_user, **moderation_action_params).call!
      redirect_to admin_group_path(@group), notice: t("admin.groups.notices.operation_restored")
    rescue Groups::RestoreOperation::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      redirect_to admin_group_path(@group), alert: t("admin.groups.alerts.operation_restore_failed")
    end

    private

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end

    def permitted_content_section
      section = params[:content].to_s
      %w[general book comments].include?(section) ? section : "all"
    end
  end
end
