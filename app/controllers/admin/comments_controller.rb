module Admin
  class CommentsController < ApplicationController
    before_action :set_comment

    def hide
      authorize @comment, :hide?
      Comments::Hide.new(@comment, actor: current_user, **moderation_action_params).call!

      respond_to do |format|
        format.turbo_stream do
          prepare_comment_moderation_history
          flash.now[:notice] = t("comments.moderation.notices.hidden")
          render "comments/moderation"
        end
        format.html { redirect_to jjaek_path(@jjaek), notice: t("comments.moderation.notices.hidden") }
      end
    rescue Comments::Hide::Error, ActiveRecord::RecordInvalid
      @comment.reload
      respond_to do |format|
        format.turbo_stream do
          prepare_comment_moderation_history
          flash.now[:alert] = t("comments.moderation.alerts.hide_failed")
          render "comments/moderation"
        end
        format.html { redirect_to jjaek_path(@jjaek), alert: t("comments.moderation.alerts.hide_failed") }
      end
    end

    def restore
      authorize @comment, :restore?
      Comments::Restore.new(@comment, actor: current_user, **moderation_action_params).call!

      respond_to do |format|
        format.turbo_stream do
          prepare_comment_moderation_history
          flash.now[:notice] = t("comments.moderation.notices.restored")
          render "comments/moderation"
        end
        format.html { redirect_to jjaek_path(@jjaek), notice: t("comments.moderation.notices.restored") }
      end
    rescue Comments::Restore::Error, ActiveRecord::RecordInvalid
      @comment.reload
      respond_to do |format|
        format.turbo_stream do
          prepare_comment_moderation_history
          flash.now[:alert] = t("comments.moderation.alerts.restore_failed")
          render "comments/moderation"
        end
        format.html { redirect_to jjaek_path(@jjaek), alert: t("comments.moderation.alerts.restore_failed") }
      end
    end

    private

    def prepare_comment_moderation_history
      actions = @comment.moderation_actions.where(action_type: %i[hide restore])
      @comment_moderation_histories = {
        @comment.id => actions.includes(:actor).order(created_at: :asc, id: :asc).to_a
      }
    end

    def set_comment
      @jjaek = Jjaek.find(params[:jjaek_id])
      @comment = @jjaek.comments.find(params[:id])
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
