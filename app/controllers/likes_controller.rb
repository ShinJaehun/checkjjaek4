class LikesController < ApplicationController
  before_action :set_post

  def create
    @like = @post.likes.find_or_initialize_by(user: current_user)
    authorize @like

    if @like.persisted? || @like.save
      redirect_back fallback_location: root_path, notice: t("likes.notices.created")
    else
      redirect_back fallback_location: root_path, alert: @like.errors.full_messages.to_sentence
    end
  end

  def destroy
    @like = @post.likes.find_by(user: current_user)

    unless @like
      redirect_back fallback_location: root_path, alert: t("likes.alerts.not_found")
      return
    end

    authorize @like
    @like.destroy!

    redirect_back fallback_location: root_path, notice: t("likes.notices.destroyed")
  end

  private

  def set_post
    @post = Post.find(params[:post_id])
    authorize @post, :show?
  end
end
