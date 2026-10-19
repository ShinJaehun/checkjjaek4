module HomeFeedContext
  private

  def prepare_home_feed
    @feed_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::FeedScope)
      .includes(:book, :likes, :comments, :moderation_actions, user: { avatar_attachment: :blob }, target_user: { avatar_attachment: :blob }, quoted_jjaek: [ { user: { avatar_attachment: :blob } }, :book, :group ])
      .recent
    @feed_book_activities = policy_scope(BookActivity, policy_scope_class: BookActivityPolicy::FeedScope)
      .includes(:book, user: { avatar_attachment: :blob })
      .recent
    @feed_items = (@feed_jjaeks.to_a + @feed_book_activities.to_a).sort_by(&:created_at).reverse
    prepare_current_reading_states_for(@feed_jjaeks)
    prepare_visible_requote_counts_for(@feed_jjaeks)
  end
end
