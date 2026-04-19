class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    authorize @user, :show?
    @posts = policy_scope(
      @user.posts,
      policy_scope_class: PostPolicy::ProfileScope
    ).recent.includes(:comments, :likes)
  end
end
