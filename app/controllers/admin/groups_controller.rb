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
  end
end
