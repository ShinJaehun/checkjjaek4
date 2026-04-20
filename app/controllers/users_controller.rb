class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    authorize @user, :show?
    @jjaeks = policy_scope(@user.jjaeks.includes(:user, :book, :likes, :comments, :quoted_jjaek)).recent
    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
  end
end
