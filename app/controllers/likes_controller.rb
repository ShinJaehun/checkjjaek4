class LikesController < ApplicationController
  before_action :set_jjaek

  def create
    @like = @jjaek.likes.find_or_initialize_by(user: current_user)
    authorize @like

    saved = if @like.persisted?
      true
    elsif @jjaek.group
      @jjaek.group.with_lock do
        authorize @like
        @like.save
      end
    else
      @like.save
    end

    if saved
      @jjaek.reload
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: root_path, notice: t("likes.notices.created") }
      end
    else
      redirect_back fallback_location: root_path, alert: @like.errors.full_messages.to_sentence
    end
  end

  def destroy
    @like = @jjaek.likes.find_by(user: current_user)

    unless @like
      redirect_back fallback_location: root_path, alert: t("likes.alerts.not_found")
      return
    end

    authorize @like
    @like.destroy!

    @jjaek.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path, notice: t("likes.notices.destroyed") }
    end
  end

  private

  def set_jjaek
    @jjaek = Jjaek.find(params[:jjaek_id])
    return if action_name == "destroy" && @jjaek.hidden?

    authorize @jjaek, :show?
  end
end
