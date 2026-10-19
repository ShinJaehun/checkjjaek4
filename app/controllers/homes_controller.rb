class HomesController < ApplicationController
  include HomeFeedContext

  before_action :prepare_feed_response_format, only: :show

  def show
    authorize :home, :show?
    prepare_home_feed
    return render_feed_page(context: :home, next_url: root_path(cursor: @feed_page.next_cursor)) if feed_page_request?

    @jjaek = Jjaek.new(user: current_user)
  end
end
