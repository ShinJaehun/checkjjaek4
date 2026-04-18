class LikesController < ApplicationController
  before_action :set_post

  def create
    @like = @post.likes.find_or_initialize_by(user: current_user)
    authorize @like
    @like.save

    redirect_back fallback_location: root_path, notice: t("likes.notices.created")
  end

  def destroy
    @like = @post.likes.find_by!(user: current_user)
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
