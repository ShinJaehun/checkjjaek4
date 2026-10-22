module Groups
  class ApplicationCancellationsController < ApplicationController
    def create
      @group = policy_scope(Group).find(params[:group_id])
      authorize @group, :cancel_application?

      # Match account withdrawal's User -> Group lock order before writing an event attributed to the applicant.
      current_user.with_lock do
        @group.with_lock do
          authorize @group, :cancel_application?
          @group.update!(lifecycle_status: :cancelled)
          event = @group.lifecycle_events.create!(actor: current_user, event_type: :opening_cancelled)
          recipient_ids = User.where(global_admin: true, withdrawn_at: nil, suspended_at: nil).pluck(:id)
          Notifications::GroupLifecycleNotifier.schedule(event:, recipient_ids:)
        end
      end

      redirect_to @group, notice: t("groups.notices.application_cancelled")
    rescue ActiveRecord::RecordInvalid
      redirect_to @group, alert: t("groups.alerts.application_cancellation_failed")
    end
  end
end
