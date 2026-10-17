class UsersController < ApplicationController
  include ProfileContext

  def show
    @user = User.find_by_public_param!(params[:id])
    authorize @user, :show?
    prepare_profile_context
    prepare_profile_jjaek_form(policy(@user))
  end

  private

  def prepare_profile_jjaek_form(profile_policy)
    return unless profile_policy.write_profile_jjaek?

    @profile_jjaek = Jjaek.new(
      user: current_user,
      target_user: @user,
      visibility: :book_friends
    )
    @profile_jjaek_visibility_options = %w[public_jjaek book_friends]
  end
end
