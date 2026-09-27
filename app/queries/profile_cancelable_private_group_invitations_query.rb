class ProfileCancelablePrivateGroupInvitationsQuery
  def initialize(actor:, target:)
    @actor = actor
    @target = target
  end

  def call
    return [] if @actor == @target

    GroupMembership.invited
      .where(user: @target)
      .joins(:group)
      .merge(@actor.administered_groups.private_group)
      .includes(:group)
      .order("groups.name", "groups.id")
      .select { |membership| GroupMembershipPolicy.new(@actor, membership).revoke? }
  end
end
