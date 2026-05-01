module ApplicationHelper
  def unread_notifications_count
    return 0 unless user_signed_in?

    @unread_notifications_count ||= current_user.received_notifications.unread.count
  end

  def show_notification_badge?
    unread_notifications_count.positive?
  end
end
