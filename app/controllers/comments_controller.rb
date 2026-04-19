class CommentsController < ApplicationController
  before_action :set_post
  before_action :set_comment, only: %i[update destroy]

  def create
    @comment = @post.comments.build(comment_params.merge(user: current_user))
    authorize @comment

    if @comment.save
      redirect_to post_path(@post), notice: t("comments.notices.created")
    else
      render "posts/show", status: :unprocessable_entity
    end
  end

  def update
    authorize @comment

    if @comment.update(comment_params)
      redirect_to post_path(@post), notice: t("comments.notices.updated")
    else
      render "posts/show", status: :unprocessable_entity
    end
  end

  def destroy
    authorize @comment
    @comment.destroy!

    redirect_to post_path(@post), notice: t("comments.notices.destroyed")
  end

  private

  def set_post
    @post = Post.find(params[:post_id])
    authorize @post, :show?
  end

  def set_comment
    @comment = @post.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
