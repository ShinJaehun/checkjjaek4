module Comments
  class Restore
    class Error < StandardError; end
    class InvalidState < Error; end

    def initialize(comment, actor:, public_reason:, internal_note: nil)
      @comment = comment
      @actor = actor
      @public_reason = public_reason
      @internal_note = internal_note
    end

    def call!
      comment.with_lock do
        current_hide = comment.current_hide_action
        raise InvalidState unless current_hide

        policy = CommentPolicy.new(actor, comment)
        moderation_authority = if policy.restore?
          "platform"
        elsif policy.restore_as_group_admin?
          "group"
        else
          raise InvalidState
        end

        comment.update!(hidden_at: nil)
        action = ModerationAction.create!(
          target: comment,
          actor:,
          action_type: :restore,
          public_reason:,
          moderation_authority:,
          internal_note:,
          reversal_of: current_hide
        )
        Notifications::ModerationNotifier.schedule(moderation_action: action, recipient_ids: [ comment.user_id ])
      end

      comment
    end

    private

    attr_reader :comment, :actor, :public_reason, :internal_note
  end
end
