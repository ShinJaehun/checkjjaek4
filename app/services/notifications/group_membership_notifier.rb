module Notifications
  class GroupMembershipNotifier
    ACTIONS = {
      "requested_to_join" => :group_membership_requested_to_join,
      "approved" => :group_membership_approved,
      "request_rejected" => :group_membership_request_rejected
    }.freeze

    def self.schedule(event:, recipient_ids:)
      notification_action = ACTIONS.fetch(event.event_type)
      recipient_ids = recipient_ids.uniq - [ event.actor_id ]
      return if recipient_ids.empty?

      ActiveRecord.after_all_transactions_commit do
        recipient_ids.each do |recipient_id|
          begin
            deliver_to(event:, notification_action:, recipient_id:)
          rescue StandardError => error
            Rails.logger.error(
              "Group membership notification delivery failed " \
              "event_type=#{event.event_type} event_id=#{event.id} " \
              "notification_action=#{notification_action} " \
              "recipient_id=#{recipient_id} error=#{error.class}"
            )
          end
        end
      end
    end

    def self.deliver_to(event:, notification_action:, recipient_id:)
      recipient = User.find_by(id: recipient_id)
      return unless recipient

      Notification.notify_once(recipient:, actor: event.actor, action: notification_action, notifiable: event)
    rescue ActiveRecord::RecordNotUnique
      raise unless Notification.exists?(
        recipient_id:,
        actor_id: event.actor_id,
        action: notification_action,
        notifiable: event
      )
    end

    private_class_method :deliver_to
  end
end
