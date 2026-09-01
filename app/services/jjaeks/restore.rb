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
        raise InvalidState unless restorable?(current_hide)

        jjaek.update!(hidden_at: nil)
        ModerationAction.create!(
          target: jjaek,
          actor:,
          action_type: :restore,
          public_reason:,
          internal_note:,
          reversal_of: current_hide
        )
      end

      jjaek
    end

    private

    attr_reader :jjaek, :actor, :public_reason, :internal_note

    def restorable?(current_hide)
      actor&.global_admin? && actor != jjaek.user && jjaek.hidden? && current_hide.present?
    end
  end
end
