class ProfileInvitablePrivateGroupsQuery
  def initialize(actor:, target:)
    @actor = actor
    @target = target
  end

  def call
    return [] if @actor == @target || !@target.active_account? || !@target.accepts_group_invitations?

    candidates = @actor.administered_groups.private_group.active
      .where(operation_suspended_at: nil)
      .where.not(id: GroupMembership.where(user_id: @target.id).select(:group_id))
      .where.not(id: GroupMemberBan.where(user_id: @target.id).select(:group_id))
      .order(:name, :id)

    candidates.select do |group|
      membership = group.group_memberships.build(user: @target, status: :invited)
      GroupMembershipPolicy.new(@actor, membership).invite?
    end
  end
end
