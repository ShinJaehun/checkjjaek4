class HomesController < ApplicationController
  def show
    authorize :home, :show?
    @jjaek = Jjaek.new(user: current_user)

    @feed_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::FeedScope)
      .includes(:user, :book, :target_user, :likes, :comments, :quoted_jjaek)
      .recent
  end
end
