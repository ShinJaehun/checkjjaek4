module NotificationsHelper
  def notification_message(notification)
    t("notifications.messages.#{notification.action}", actor_name: notification.actor.name)
  end

  def notification_target_path(notification)
    case notification.action
    when "book_friendship_requested"
      relationships_path(anchor: "received-book-friend-requests")
    when "profile_jjaek_created", "requote_created"
      notification.notifiable ? jjaek_path(notification.notifiable) : root_path
    when "comment_created"
      notification.notifiable ? jjaek_path(notification.notifiable.jjaek) : root_path
    else
      root_path
    end
  end
end
