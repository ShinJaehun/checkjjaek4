module Groups
  class ReactivationRequestsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      current_user.with_lock do
        @group.with_lock do
          authorize @group, :request_reactivation?
          @group.pending_approval!
          event = GroupLifecycleEvent.create!(group: @group, actor: current_user, event_type: :reactivation_requested)
          Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids: eligible_global_admin_ids)
        end
      end

      redirect_to @group, notice: t("groups.notices.reactivation_requested")
    rescue ActiveRecord::RecordInvalid
      @group.reload
      @error_message = t("groups.alerts.reactivation_request_failed")
      render :new, status: :unprocessable_content
    end

    def withdraw
      # Keep the User -> Group lock order used by account withdrawal.
      current_user.with_lock do
        @group.with_lock do
          authorize @group, :withdraw_reactivation?
          @group.update!(lifecycle_status: :inactive)
          event = @group.lifecycle_events.create!(actor: current_user, event_type: :reactivation_withdrawn)
          Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids: eligible_global_admin_ids)
        end
      end

      redirect_to edit_group_path(@group), notice: t("groups.notices.reactivation_withdrawn")
    rescue ActiveRecord::RecordInvalid
      redirect_to edit_group_path(@group), alert: t("groups.alerts.reactivation_withdrawal_failed")
    end

    private

    def prepare_page
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, action_name == "withdraw" ? :withdraw_reactivation? : :request_reactivation?
    end

    def eligible_global_admin_ids
      User.where(global_admin: true, withdrawn_at: nil, suspended_at: nil).pluck(:id)
    end
  end
end
