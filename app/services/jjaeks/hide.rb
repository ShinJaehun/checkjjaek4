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
        policy = JjaekPolicy.new(actor, jjaek)
        moderation_authority = if policy.hide?
          "platform"
        elsif policy.hide_as_group_admin?
          "group"
        else
          raise InvalidState
        end

        jjaek.update!(hidden_at: Time.current)
        ModerationAction.create!(
          target: jjaek,
          actor:,
          action_type: :hide,
          public_reason:,
          moderation_authority:,
          internal_note: moderation_authority == "platform" ? internal_note : nil
        )
      end

      jjaek
    end

    private

    attr_reader :jjaek, :actor, :public_reason, :internal_note
  end
end
