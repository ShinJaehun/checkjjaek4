class PostsController < ApplicationController
  before_action :set_post, only: %i[show edit update destroy]

  def index
    @post = current_user.posts.build
    @posts = policy_scope(Post).recent.includes(:user, :comments, :likes)
  end

  def show
    @comment = @post.comments.build
  end

  def edit
  end

  def create
    @post = current_user.posts.build(post_params)
    authorize @post

    if @post.save
      redirect_to root_path, notice: t("posts.notices.created")
    else
      @posts = policy_scope(Post).recent.includes(:user, :comments, :likes)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @post.update(post_params)
      redirect_to post_path(@post), notice: t("posts.notices.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy!
    redirect_to root_path, notice: t("posts.notices.destroyed")
  end

  private

  def set_post
    @post = Post.find(params[:id])
    authorize @post
  end

  def post_params
    params.require(:post).permit(:content)
  end
end
