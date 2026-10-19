class UsersController < ApplicationController
  include ProfileContext

  before_action :prepare_feed_response_format, only: :show

  def show
    @user = User.find_by_public_param!(params[:id])
    authorize @user, :show?
    if feed_page_request?
      prepare_profile_book_activities
      prepare_profile_jjaeks(policy(@user))
      prepare_profile_activity_items
      return render_feed_page(context: :profile, next_url: user_path(@user, cursor: @feed_page.next_cursor))
    end
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
