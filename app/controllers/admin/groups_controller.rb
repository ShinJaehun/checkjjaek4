module Admin
  class GroupsController < ApplicationController
    def index
      authorize Group, :view_admin_inventory?
      groups = policy_scope(Group, policy_scope_class: GroupPolicy::AdminInventoryScope)
      scope = GroupInventoryQuery.new(groups, params).call.includes(:group_admin)
      @inventory_page = InventoryPage.new(scope, page: params[:page])
      @groups = @inventory_page.records
    end

    def show
      @group = Group.find(params[:id])
      authorize @group, :view_admin_details?
      @lifecycle_events = @group.lifecycle_events.includes(:actor)
      @current_operation_suspension = @group.current_operation_suspension_action
      @content_section = permitted_content_section
      @content_filter_params = params.permit(:content_q, :content_status, :content_sort)

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
      @return_params = params.permit(:q, :group_type, :status, :sort, :page)
    end

    def approve
      @group = Group.find(params[:id])
      authorize @group, :approve?
      event_type = @group.closed_at.nil? ? :opening_approved : :reactivation_approved

      Group.transaction do
        @group.active!
        GroupLifecycleEvent.create!(group: @group, actor: current_user, event_type: event_type)
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
