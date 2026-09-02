module Jjaeks
  class Restore
    class Error < StandardError; end
    class InvalidState < Error; end

    def initialize(jjaek, actor:, public_reason:, internal_note: nil)
      @jjaek = jjaek
      @actor = actor
      @public_reason = public_reason
      @internal_note = internal_note
    end

    def call!
      jjaek.with_lock do
        current_hide = jjaek.current_hide_action
        raise InvalidState unless current_hide

        policy = JjaekPolicy.new(actor, jjaek)
        moderation_authority = if policy.restore?
          "platform"
        elsif policy.restore_as_group_admin?
          "group"
        else
          raise InvalidState
        end

        jjaek.update!(hidden_at: nil)
        ModerationAction.create!(
          target: jjaek,
          actor:,
          action_type: :restore,
          public_reason:,
          moderation_authority:,
          internal_note:,
          reversal_of: current_hide
        )
      end

      jjaek
    end

    private

    attr_reader :jjaek, :actor, :public_reason, :internal_note
  end
end
