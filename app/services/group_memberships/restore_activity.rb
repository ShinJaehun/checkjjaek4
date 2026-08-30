module GroupMemberships
  class RestoreActivity
    class Error < StandardError; end
    class InvalidState < Error; end

    def initialize(membership, actor:, public_reason:, internal_note: nil)
      @membership = membership
      @actor = actor
      @public_reason = public_reason
      @internal_note = internal_note
    end

    def call!
      membership.group.with_lock do
        membership.with_lock do
          suspension = membership.current_activity_suspension_action
          raise InvalidState unless membership.group.operation_active? && membership.activity_suspended? &&
                                    suspension.present? && membership.group.group_admin?(actor)

          membership.update!(moderation_status: :normal)
          ModerationAction.create!(
            target: membership,
            actor:,
            action_type: :restore_activity,
            public_reason:,
            internal_note:,
            reversal_of: suspension
          )
        end
      end

      membership
    end

    private

    attr_reader :membership, :actor, :public_reason, :internal_note
  end
end
