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
          raise InvalidState unless UserPolicy.new(actor, user).restore?

          suspension = user.current_suspension_action
          raise InvalidState if suspension.nil?

          user.update!(suspended_at: nil)
          action = ModerationAction.create!(
            target: user,
            actor:,
            action_type: :restore,
            public_reason:,
            internal_note:,
            reversal_of: suspension
          )
          Notifications::ModerationNotifier.schedule(moderation_action: action, recipient_ids: [ user.id ])
        end
      end

      user
    end

    private

    attr_reader :user, :actor, :public_reason, :internal_note
  end
end
