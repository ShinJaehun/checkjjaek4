class CommentsController < ApplicationController
  before_action :set_post

  def create
    @comment = @post.comments.build(comment_params.merge(user: current_user))
    authorize @comment

    if @comment.save
      redirect_to post_path(@post), notice: t("comments.notices.created")
    else
      redirect_to post_path(@post), alert: @comment.errors.full_messages.to_sentence
    end
  end

  def update
    @comment = @post.comments.find(params[:id])
    authorize @comment

    if @comment.update(comment_params)
      redirect_to post_path(@post), notice: t("comments.notices.updated")
    else
      redirect_to post_path(@post), alert: @comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    @comment = @post.comments.find(params[:id])
    authorize @comment
    @comment.destroy!

    redirect_to post_path(@post), notice: t("comments.notices.destroyed")
  end

  private

  def set_post
    @post = Post.find(params[:post_id])
    authorize @post, :show?
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
