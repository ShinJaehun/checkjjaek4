module Jjaeks
  class Hide
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
        raise InvalidState unless actor&.global_admin? && actor != jjaek.user && !jjaek.hidden?

        jjaek.update!(hidden_at: Time.current)
        ModerationAction.create!(target: jjaek, actor:, action_type: :hide, public_reason:, internal_note:)
      end

      jjaek
    end

    private

    attr_reader :jjaek, :actor, :public_reason, :internal_note
  end
end
