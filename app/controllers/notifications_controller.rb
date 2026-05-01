class NotificationsController < ApplicationController
  def index
    authorize Notification
    @notifications = policy_scope(Notification).includes(:actor, :notifiable).recent.to_a
    @unread_notification_ids = @notifications.filter_map { |notification| notification.id if notification.unread? }
    mark_notifications_as_read
  end

  private

  def mark_notifications_as_read
    Notification.where(id: @unread_notification_ids).update_all(read_at: Time.current, updated_at: Time.current)
  end
end
