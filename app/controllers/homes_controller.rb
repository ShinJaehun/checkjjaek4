class HomesController < ApplicationController
  def show
    authorize :home, :show?
    @jjaek = Jjaek.new(user: current_user)

    @feed_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::FeedScope)
      .includes(:user, :book, :target_user, :likes, :comments, :quoted_jjaek)
      .recent
    @feed_book_activities = policy_scope(BookActivity)
      .includes(:user, :book)
      .recent
    @feed_items = (@feed_jjaeks.to_a + @feed_book_activities.to_a).sort_by(&:created_at).reverse
    prepare_visible_requote_counts_for(@feed_jjaeks)
  end
end
