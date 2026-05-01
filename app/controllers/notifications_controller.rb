class NotificationsController < ApplicationController
  def index
    authorize Notification
    @notifications = policy_scope(Notification).includes(:actor, :notifiable).recent
    mark_notifications_as_read
  end

  private

  def mark_notifications_as_read
    @notifications.unread.update_all(read_at: Time.current, updated_at: Time.current)
  end
end
