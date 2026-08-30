module Groups
  class RestoreOperation
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
        original_action = group.current_operation_suspension_action
        raise InvalidState unless actor&.global_admin? && group.operation_suspended? && original_action

        ModerationAction.create!(
          target: group,
          actor:,
          action_type: :restore_group_operation,
          public_reason:,
          internal_note:,
          reversal_of: original_action
        )
        group.update!(operation_suspended_at: nil)
      end
      group
    end

    private

    attr_reader :group, :actor, :public_reason, :internal_note
  end
end
