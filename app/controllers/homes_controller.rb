class HomesController < ApplicationController
  include HomeFeedContext

  def show
    authorize :home, :show?
    @jjaek = Jjaek.new(user: current_user)
    prepare_home_feed
  end
end
