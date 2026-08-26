module Admin
  class GroupsController < ApplicationController
    def index
      authorize Group, :manage_approvals?
      @groups = Group.pending_approval.includes(:owner).order(updated_at: :asc)
    end

    def approve
      @group = Group.find(params[:id])
      authorize @group, :approve?
      @group.active!

      redirect_to admin_groups_path, notice: t("admin.groups.notices.approved")
    end
  end
end
