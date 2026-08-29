module Users
  class SuspendAccount
    class Error < StandardError; end
    class InvalidState < Error; end

    def initialize(user, actor:, public_reason:, internal_note: nil)
      @user = user
      @actor = actor
      @public_reason = public_reason
      @internal_note = internal_note
    end

    def call!
      User.transaction do
        user.with_lock do
          raise InvalidState if user.withdrawn? || user.suspended?

          user.update!(suspended_at: Time.current)
          ModerationAction.create!(
            target: user,
            actor:,
            action_type: :suspend,
            public_reason:,
            internal_note:
          )
        end
      end

      user
    end

    private

    attr_reader :user, :actor, :public_reason, :internal_note
  end
end
