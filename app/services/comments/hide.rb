module Comments
  class Hide
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
        policy = CommentPolicy.new(actor, comment)
        moderation_authority = if policy.hide?
          "platform"
        elsif policy.hide_as_group_admin?
          "group"
        else
          raise InvalidState
        end

        comment.update!(hidden_at: Time.current)
        action = ModerationAction.create!(
          target: comment,
          actor:,
          action_type: :hide,
          public_reason:,
          moderation_authority:,
          internal_note:
        )
        Notifications::ModerationNotifier.schedule(moderation_action: action, recipient_ids: [ comment.user_id ])
      end

      comment
    end

    private

    attr_reader :comment, :actor, :public_reason, :internal_note
  end
end
