class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    authorize @user, :show?
    @posts = policy_scope(@user.posts).recent.includes(:comments, :likes)
  end
end
