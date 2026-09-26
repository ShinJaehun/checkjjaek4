module Notifications
  class ModerationNotifier
    ACTIONS = {
      [ "User", "suspend" ] => :user_account_suspended,
      [ "User", "restore" ] => :user_account_restored,
      [ "Group", "suspend_group_operation" ] => :group_operation_suspended,
      [ "Group", "restore_group_operation" ] => :group_operation_restored,
      [ "GroupMembership", "suspend_activity" ] => :group_member_activity_suspended,
      [ "GroupMembership", "restore_activity" ] => :group_member_activity_restored,
      [ "Jjaek", "hide" ] => :jjaek_hidden,
      [ "Jjaek", "restore" ] => :jjaek_restored,
      [ "Comment", "hide" ] => :comment_hidden,
      [ "Comment", "restore" ] => :comment_restored
    }.freeze

    def self.schedule(moderation_action:, recipient_ids:)
      recipient_ids = recipient_ids.uniq - [ moderation_action.actor_id ]
      return if recipient_ids.empty?

      ActiveRecord.after_all_transactions_commit do
        recipient_ids.each do |recipient_id|
          begin
            notification_action = ACTIONS.fetch([ moderation_action.target_type, moderation_action.action_type ])
            deliver_to(moderation_action:, notification_action:, recipient_id:)
          rescue StandardError => error
            Rails.logger.error(
              "Moderation notification delivery failed " \
              "moderation_action_id=#{moderation_action.id} " \
              "notification_action=#{notification_action || moderation_action.action_type} " \
              "recipient_id=#{recipient_id} error=#{error.class}"
            )
          end
        end
      end
    end

    def self.deliver_to(moderation_action:, notification_action:, recipient_id:)
      recipient = User.find_by(id: recipient_id)
      return unless recipient

      Notification.notify_once(
        recipient:,
        actor: moderation_action.actor,
        action: notification_action,
        notifiable: moderation_action
      )
    rescue ActiveRecord::RecordNotUnique
      raise unless Notification.exists?(
        recipient_id:,
        actor_id: moderation_action.actor_id,
        action: notification_action,
        notifiable: moderation_action
      )
    end

    private_class_method :deliver_to
  end
end
