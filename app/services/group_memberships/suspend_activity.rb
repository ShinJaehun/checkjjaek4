module GroupMemberships
  class SuspendActivity
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
          raise InvalidState unless membership.active? && membership.moderation_status_normal?
          raise InvalidState unless membership.group.group_admin?(actor)
          raise InvalidState if membership.user_id == membership.group.group_admin_id

          membership.update!(moderation_status: :activity_suspended)
          ModerationAction.create!(
            target: membership,
            actor:,
            action_type: :suspend_activity,
            public_reason:,
            internal_note:
          )
        end
      end

      membership
    end

    private

    attr_reader :membership, :actor, :public_reason, :internal_note
  end
end
