module HomeFeedContext
  private

  def prepare_home_feed
    @feed_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::FeedScope)
      .includes(:attached_books, user: { avatar_attachment: :blob }, target_user: { avatar_attachment: :blob }, quoted_jjaek: [ { user: { avatar_attachment: :blob } }, :attached_books, :group ])
      .recent
    @feed_book_activities = policy_scope(BookActivity, policy_scope_class: BookActivityPolicy::FeedScope)
      .includes(:book, user: { avatar_attachment: :blob })
      .recent
    @feed_page = FeedPage.new(jjaeks: @feed_jjaeks, book_activities: @feed_book_activities, cursor: params[:cursor])
    @feed_next_url = root_path(cursor: @feed_page.next_cursor) if @feed_page.next_cursor
    @feed_items = @feed_page.items
    @feed_jjaeks = @feed_items.grep(Jjaek)
    prepare_jjaek_card_summaries_for(@feed_jjaeks)
    prepare_current_reading_states_for(@feed_jjaeks)
    prepare_visible_requote_counts_for(@feed_jjaeks)
    prepare_group_share_destinations_for(@feed_jjaeks)
  end
end
