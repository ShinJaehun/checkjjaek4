class CommentsController < ApplicationController
  before_action :set_jjaek
  before_action :set_comment, only: %i[update destroy]

  def create
    @comment = @jjaek.comments.build(comment_params.merge(user: current_user))
    authorize @comment

    if @comment.save
      redirect_to jjaek_path(@jjaek), notice: t("comments.notices.created")
    else
      @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
      render "jjaeks/show", status: :unprocessable_entity
    end
  end

  def update
    authorize @comment

    if @comment.update(comment_params)
      redirect_to jjaek_path(@jjaek), notice: t("comments.notices.updated")
    else
      @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
      render "jjaeks/show", status: :unprocessable_entity
    end
  end

  def destroy
    authorize @comment
    @comment.destroy!

    redirect_to jjaek_path(@jjaek), notice: t("comments.notices.destroyed")
  end

  private

  def set_jjaek
    @jjaek = Jjaek.find(params[:jjaek_id])
    authorize @jjaek, :show?
  end

  def set_comment
    @comment = @jjaek.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
