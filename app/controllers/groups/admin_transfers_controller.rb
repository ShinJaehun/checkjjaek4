module Groups
  class AdminTransfersController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      new_admin = @group.group_memberships.active.includes(:user).find_by(user_id: params[:new_admin_id])&.user
      @group.transfer_admin_to!(new_admin, by: current_user)

      redirect_to transfer_redirect_path, notice: t("groups.notices.admin_transferred")
    rescue ActiveRecord::RecordInvalid
      @selected_admin_id = params[:new_admin_id]
      @error_message = t("groups.alerts.admin_transfer_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, :transfer_admin?
      @admin_transfer_candidates = @group.active_group_memberships
        .moderation_status_normal
        .where.not(user_id: @group.group_admin_id)
        .includes(:user)
        .map(&:user)
        .sort_by(&:name)
    end

    def transfer_redirect_path
      policy(@group).view_admin_details? ? admin_group_path(@group) : group_path(@group)
    end
  end
end
