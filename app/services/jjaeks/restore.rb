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
        policy = JjaekPolicy.new(actor, jjaek)
        raise InvalidState unless restorable?(current_hide, policy)

        jjaek.update!(hidden_at: nil)
        ModerationAction.create!(
          target: jjaek,
          actor:,
          action_type: :restore,
          public_reason:,
          moderation_authority: policy.restore? ? "platform" : "group",
          internal_note: policy.restore? ? internal_note : nil,
          reversal_of: current_hide
        )
      end

      jjaek
    end

    private

    attr_reader :jjaek, :actor, :public_reason, :internal_note

    def restorable?(current_hide, policy)
      current_hide.present? && (policy.restore? || policy.restore_as_group_admin?)
    end
  end
end
