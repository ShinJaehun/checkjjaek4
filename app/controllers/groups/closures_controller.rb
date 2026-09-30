module Groups
  class ClosuresController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      @closure_reason_input = closure_params[:closure_reason]

      closed = @group.with_lock do
        authorize @group, :close?
        recipient_ids = @group.group_memberships.active.distinct.pluck(:user_id)
        next false unless @group.update(
          lifecycle_status: :inactive,
          closure_reason: @closure_reason_input,
          closed_at: Time.current
        )

        event = GroupLifecycleEvent.create!(
          group: @group,
          actor: current_user,
          event_type: :operations_closed,
          detail: @closure_reason_input
        )
        Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids:)
        true
      end

      if closed
        redirect_to @group, notice: t("groups.notices.closed")
      else
        restore_group_state
        render :new, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordInvalid
      restore_group_state
      @error_message = t("groups.alerts.close_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, :close?
    end

    def closure_params
      params.fetch(:group, {}).permit(:closure_reason)
    end

    def restore_group_state
      @group.restore_attributes(%w[lifecycle_status closed_at])
    end
  end
end
