module Admin
  class GroupOperationRestorationsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      Groups::RestoreOperation.new(@group, actor: current_user, **action_params).call!
      redirect_to admin_group_path(@group, @return_params), notice: t("admin.groups.notices.operation_restored")
    rescue Groups::RestoreOperation::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @error_message = t("admin.groups.alerts.operation_restore_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @group = Group.find(params[:group_id])
      authorize @group, :restore_operation?
      @current_operation_suspension = @group.current_operation_suspension_action
      @moderation_action = ModerationAction.new
      @return_params = params.permit(:q, :group_type, :status, :operation_status, :sort, :page)
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
