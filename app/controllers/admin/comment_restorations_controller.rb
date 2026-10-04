module Admin
  class CommentRestorationsController < ApplicationController
    before_action :prepare_page

    def new; end

    def create
      action_params = moderation_action_params
      @moderation_action.assign_attributes(action_params)
      Comments::Restore.new(@comment, actor: current_user, **action_params).call!

      redirect_to return_path, notice: t("comments.moderation.notices.restored")
    rescue Comments::Restore::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @comment.reload
      @current_hide_action = @comment.current_hide_action
      @error_message = t("comments.moderation.alerts.restore_failed")
      render :new, status: :unprocessable_content
    end

    private

    def prepare_page
      @jjaek = Jjaek.find(params[:jjaek_id])
      authorize @jjaek, :show?

      @comment = @jjaek.comments.find_by(id: params[:comment_id])
      unless @comment
        redirect_to jjaek_path(@jjaek), alert: t("comments.moderation.alerts.stale_action")
        return
      end

      authorize @comment, :restore?
      @current_hide_action = @comment.current_hide_action
      @moderation_action = ModerationAction.new
    end

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end

    def return_path
      jjaek_path(@jjaek, anchor: ActionView::RecordIdentifier.dom_id(@comment))
    end
  end
end
