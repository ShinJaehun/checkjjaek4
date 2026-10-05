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
      @operation_moderation_actions = ModerationAction
        .where(target: @group, action_type: %i[suspend_group_operation restore_group_operation])
        .includes(:actor)
        .order(:created_at, :id)
        .to_a
      @can_suspend_operation = policy(@group).suspend_operation?
      @can_restore_operation = policy(@group).restore_operation?
      @membership_counts = @group.group_memberships.group(:status).count
      admin_membership_active = @group.active_group_memberships.exists?(user_id: @group.group_admin_id)
      @active_member_count = @membership_counts.fetch("active", 0) - (admin_membership_active ? 1 : 0)
      @member_preview = @group.active_group_memberships.where.not(user_id: @group.group_admin_id)
        .includes(:user).order(:created_at, :id).limit(5).map(&:user)
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

    private

    def permitted_content_section
      section = params[:content].to_s
      %w[general book comments].include?(section) ? section : "all"
    end
  end
end
