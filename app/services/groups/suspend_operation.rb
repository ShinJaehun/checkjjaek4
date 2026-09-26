module Groups
  class SuspendOperation
    class Error < StandardError; end
    class InvalidState < Error; end

    def initialize(group, actor:, public_reason:, internal_note: nil)
      @group = group
      @actor = actor
      @public_reason = public_reason
      @internal_note = internal_note
    end

    def call!
      group.with_lock do
        raise InvalidState unless GroupPolicy.new(actor, group).suspend_operation?
        raise InvalidState unless Group::SUSPENSION_REASONS.include?(public_reason)

        recipient_ids = group.group_memberships.active.distinct.pluck(:user_id)
        group.update!(operation_suspended_at: Time.current)
        action = ModerationAction.create!(target: group, actor:, action_type: :suspend_group_operation, public_reason:, internal_note:)
        Notifications::ModerationNotifier.schedule(moderation_action: action, recipient_ids:)
      end
      group
    end

    private

    attr_reader :group, :actor, :public_reason, :internal_note
  end
end
