module Notifications
  class GroupLifecycleNotifier
    ACTIONS = {
      [ "GroupLifecycleEvent", "opening_requested" ] => :group_opening_requested,
      [ "GroupLifecycleEvent", "opening_approved" ] => :group_opening_approved,
      [ "GroupLifecycleEvent", "operations_closed" ] => :group_operations_closed,
      [ "GroupLifecycleEvent", "reactivation_requested" ] => :group_reactivation_requested,
      [ "GroupLifecycleEvent", "reactivation_approved" ] => :group_reactivation_approved,
      [ "GroupMembershipEvent", "admin_role_revoked" ] => :group_admin_role_revoked,
      [ "GroupMembershipEvent", "admin_role_granted" ] => :group_admin_role_granted
    }.freeze

    def self.schedule(event:, recipient_ids:)
      notification_action = ACTIONS.fetch([ event.class.name, event.event_type ])
      recipient_ids = recipient_ids.uniq - [ event.actor_id ]
      return if recipient_ids.empty?

      ActiveRecord.after_all_transactions_commit do
        recipient_ids.each do |recipient_id|
          begin
            deliver_to(event:, notification_action:, recipient_id:)
          rescue StandardError => error
            Rails.logger.error(
              "Group lifecycle notification delivery failed " \
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
