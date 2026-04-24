class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    authorize @user, :show?
    profile_policy = policy(@user)

    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    @show_bookshelf = profile_policy.show_profile_bookshelf?
    @show_profile_bookshelf_status = profile_policy.show_profile_bookshelf_status?
    @bookshelf_entries =
      if @show_bookshelf
        policy_scope(@user.bookshelf_entries, policy_scope_class: BookshelfEntryPolicy::ProfileScope).recent_first
      end

    @show_jjaeks = profile_policy.show_profile_jjaeks?
    @jjaeks =
      if @show_jjaeks
        resolve_profile_jjaeks(profile_policy.profile_access_level)
      else
        Jjaek.none
      end

    if profile_policy.write_profile_jjaek?
      @profile_jjaek = current_user.jjaeks.build(
        target_user: @user,
        visibility: profile_jjaek_default_visibility
      )
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

  def resolve_profile_jjaeks(access_level)
    scope = policy_scope(@user.jjaeks).includes(:user, :book, :likes, :comments, :quoted_jjaek)

    case access_level
    when :following
      scope.where(visibility: Jjaek.visibilities[:public_jjaek]).recent
    else
      scope.recent
    end
  end
end
