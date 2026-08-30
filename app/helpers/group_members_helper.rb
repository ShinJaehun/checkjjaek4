module GroupMembersHelper
  def membership_history_description(entry)
    record = entry.fetch(:record)
    user = entry.fetch(:user)

    if entry.fetch(:source) == :lifecycle
      t(
        "groups.members.history.lifecycle.#{record.event_type}",
        actor: record.actor.name,
        user: user.name
      )
    else
      t(
        "groups.members.history.moderation.#{record.action_type}",
        actor: record.actor.name,
        user: user.name
      )
    end
  end
end
