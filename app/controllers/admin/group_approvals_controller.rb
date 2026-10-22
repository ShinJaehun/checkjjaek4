module Admin
  class GroupApprovalsController < ApplicationController
    before_action :prepare_page
    rescue_from ActiveRecord::RecordNotFound do
      redirect_to admin_groups_path(@return_params), alert: t("groups.alerts.not_found_or_inaccessible")
    end

    def new; end

    def create
      @group.with_lock do
        authorize @group, :approve?
        event_type = @group.closed_at.nil? ? :opening_approved : :reactivation_approved
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

      redirect_to @approval_return_path, notice: t("admin.groups.notices.approved")
    rescue ActiveRecord::RecordInvalid
      @group.reload
      @error_message = t("admin.groups.alerts.approval_failed")
      render :new, status: :unprocessable_content
    end

    def reject
      @rejection_event.detail = params.fetch(:group_lifecycle_event, {}).permit(:detail)[:detail]
      @group.with_lock do
        authorize @group, :reject?
        @rejection_event.event_type = @group.pending_reactivation_request? ? :reactivation_rejected : :opening_rejected
        @group.update!(lifecycle_status: @group.pending_reactivation_request? ? :inactive : :rejected)
        @rejection_event.save!
        Notifications::GroupLifecycleNotifier.schedule(event: @rejection_event, recipient_ids: [ @group.group_admin_id ])
      end

      notice_key = @rejection_event.reactivation_rejected? ? "reactivation_rejected" : "rejected"
      redirect_to @approval_return_path, notice: t("admin.groups.notices.#{notice_key}")
    rescue ActiveRecord::RecordInvalid
      @group.reload
      error_key = @group.pending_reactivation_request? ? "reactivation_rejection_failed" : "rejection_failed"
      @error_message = t("admin.groups.alerts.#{error_key}")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      authorize Group, :manage_approvals?
      @return_params = params.permit(:q, :group_type, :status, :operation_status, :sort, :page)
      @group = Group.find_by(id: params[:group_id])

      unless @group
        redirect_to admin_groups_path(@return_params), alert: t("groups.alerts.not_found_or_inaccessible")
        return
      end

      authorize @group, action_name == "reject" ? :reject? : :approve?
      event_type = @group.pending_reactivation_request? ? :reactivation_rejected : :opening_rejected
      @rejection_event = GroupLifecycleEvent.new(group_id: @group.id, actor: current_user, event_type:)
      @action_params = @return_params.to_h
      @action_params[:return_to] = "inventory" if params[:return_to] == "inventory"
      @approval_return_path = if params[:return_to] == "inventory"
        admin_groups_path(@return_params)
      else
        admin_group_path(@group, @return_params)
      end
    end
  end
end
