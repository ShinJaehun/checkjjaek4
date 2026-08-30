module GroupMemberBans
  class Unban
    class Error < StandardError; end
    class InvalidState < Error; end

    def initialize(ban, actor:, public_reason:, internal_note: nil)
      @ban = ban
      @actor = actor
      @public_reason = public_reason
      @internal_note = internal_note
    end

    def call!
      ban.group.with_lock do
        ban.lock!
        original_action = ban.current_ban_action
        raise InvalidState unless ban.group.active? &&
                                  ban.group.group_admin?(actor) &&
                                  original_action

        ModerationAction.create!(
          target: ban,
          actor:,
          action_type: :unban_from_group,
          public_reason:,
          internal_note:,
          reversal_of: original_action
        )
        ban.destroy!
      end
    end

    private

    attr_reader :ban, :actor, :public_reason, :internal_note
  end
end
