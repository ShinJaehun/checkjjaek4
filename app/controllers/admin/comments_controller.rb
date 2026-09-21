module Admin
  class CommentsController < ApplicationController
    before_action :set_comment

    def hide
      authorize @comment, :hide?
      Comments::Hide.new(@comment, actor: current_user, **moderation_action_params).call!

      redirect_to jjaek_path(@jjaek), notice: t("comments.moderation.notices.hidden")
    rescue Comments::Hide::Error, ActiveRecord::RecordInvalid
      redirect_to jjaek_path(@jjaek), alert: t("comments.moderation.alerts.hide_failed")
    end

    def restore
      authorize @comment, :restore?
      Comments::Restore.new(@comment, actor: current_user, **moderation_action_params).call!

      redirect_to jjaek_path(@jjaek), notice: t("comments.moderation.notices.restored")
    rescue Comments::Restore::Error, ActiveRecord::RecordInvalid
      redirect_to jjaek_path(@jjaek), alert: t("comments.moderation.alerts.restore_failed")
    end

    private

    def set_comment
      @jjaek = Jjaek.find(params[:jjaek_id])
      @comment = @jjaek.comments.find(params[:id])
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
