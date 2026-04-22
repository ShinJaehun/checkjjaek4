class HomesController < ApplicationController
  def show
    authorize :home, :show?
    @jjaek = current_user.jjaeks.build

    @feed_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::FeedScope)
      .includes(:user, :book, :likes, :comments, :quoted_jjaek)
      .recent
  end
end
