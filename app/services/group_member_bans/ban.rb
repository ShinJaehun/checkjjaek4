module GroupMemberBans
  class Ban
    class Error < StandardError; end
    class InvalidState < Error; end

    def initialize(membership, actor:, public_reason:, internal_note: nil)
      @membership = membership
      @actor = actor
      @public_reason = public_reason
      @internal_note = internal_note
    end

    def call!
      group.with_lock do
        membership.lock!
        raise InvalidState unless group.active? && group.operation_active? && group.group_admin?(actor)
        raise InvalidState if membership.user_id == group.group_admin_id
        raise InvalidState unless membership.pending? || membership.invited? || membership.active?

        ban = group.group_member_bans.create!(user: membership.user)
        ModerationAction.create!(
          target: ban,
          actor:,
          action_type: :ban_from_group,
          public_reason:,
          internal_note:
        )
        GroupMembershipRemoval.where(group:, user: membership.user).delete_all
        membership.destroy!
        ban
      end
    end

    private

    attr_reader :membership, :actor, :public_reason, :internal_note

    def group
      membership.group
    end
  end
end
