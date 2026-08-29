module Users
  class RestoreAccount
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
          suspension = user.current_suspension_action
          raise InvalidState if user.withdrawn? || !user.suspended? || suspension.nil?

          user.update!(suspended_at: nil)
          ModerationAction.create!(
            target: user,
            actor:,
            action_type: :restore,
            public_reason:,
            internal_note:,
            reversal_of: suspension
          )
        end
      end

      user
    end

    private

    attr_reader :user, :actor, :public_reason, :internal_note
  end
end
