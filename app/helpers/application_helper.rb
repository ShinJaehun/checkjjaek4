module ApplicationHelper
  def received_book_friend_requests_count
    return 0 unless user_signed_in?

    @received_book_friend_requests_count ||= current_user.received_book_friendships.pending.count
  end

  def show_relationship_notification_badge?
    received_book_friend_requests_count.positive?
  end

  def relationships_nav_path
    return relationships_path unless show_relationship_notification_badge?

    "#{relationships_path}#received-book-friend-requests"
  end
end
