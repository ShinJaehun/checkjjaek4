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
        raise InvalidState unless actor&.global_admin? && group.active? && group.operation_active?

        group.update!(operation_suspended_at: Time.current)
        ModerationAction.create!(target: group, actor:, action_type: :suspend_group_operation, public_reason:, internal_note:)
      end
      group
    end

    private

    attr_reader :group, :actor, :public_reason, :internal_note
  end
end
