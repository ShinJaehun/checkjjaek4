module Admin
  class GroupsController < ApplicationController
    def index
      authorize Group, :manage_approvals?
      @pending_groups = Group.pending_approval.includes(:group_admin, lifecycle_events: :actor).order(updated_at: :asc)
      @all_groups = Group.includes(:group_admin).order(updated_at: :desc)
    end

    def show
      @group = Group.find(params[:id])
      authorize @group, :view_admin_details?
      @lifecycle_events = @group.lifecycle_events.includes(:actor)
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
