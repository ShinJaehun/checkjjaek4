class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    authorize @user, :show?
    @jjaeks = policy_scope(@user.jjaeks.includes(:user, :book, :likes, :comments, :quoted_jjaek)).recent
    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    @show_bookshelf = policy(@user).show_bookshelf?
    @bookshelf_entries = policy_scope(@user.bookshelf_entries).recent_first if @show_bookshelf

    if policy(@user).write_jjaek?
      @profile_jjaek = current_user.jjaeks.build(visibility: profile_jjaek_default_visibility)
      @profile_jjaek_visibility_options = profile_jjaek_visibility_options
    end
  end

  private

  def profile_jjaek_default_visibility
    current_user == @user ? :public_jjaek : :book_friends
  end

  def profile_jjaek_visibility_options
    options = %w[public_jjaek book_friends]
    options << "private_jjaek" if current_user == @user
    options
  end
end
