module Groups
  class ReactivationRequestsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      Group.transaction do
        @group.pending_approval!
        event = GroupLifecycleEvent.create!(group: @group, actor: current_user, event_type: :reactivation_requested)
        Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids: eligible_global_admin_ids)
        event
      end

      redirect_to @group, notice: t("groups.notices.reactivation_requested")
    rescue ActiveRecord::RecordInvalid
      @group.reload
      @error_message = t("groups.alerts.reactivation_request_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, :request_reactivation?
    end

    def eligible_global_admin_ids
      User.where(global_admin: true, withdrawn_at: nil, suspended_at: nil).pluck(:id)
    end
  end
end
