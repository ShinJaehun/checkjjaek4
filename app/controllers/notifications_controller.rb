class NotificationsController < ApplicationController
  def index
    authorize Notification
    @notifications = policy_scope(Notification).includes(:notifiable, actor: { avatar_attachment: :blob }).recent.to_a
    @unread_notification_ids = @notifications.filter_map { |notification| notification.id if notification.unread? }
    mark_notifications_as_read
  end

  private

  def mark_notifications_as_read
    return if @unread_notification_ids.empty?

    unread_notifications = current_user.received_notifications.unread.where(id: @unread_notification_ids)
    updated_count = unread_notifications.update_all(read_at: Time.current, updated_at: Time.current)
    Notification.broadcast_badge_to(current_user) if updated_count.positive?
  end
end
