module GroupMembersHelper
  include ::UsersHelper

  def group_membership_role_label(role)
    return user_role_label(:group_admin) if role.to_s == "admin"

    t("groups.members.roles.member")
  end

  def group_membership_role_badge_classes(role)
    user_role_badge_classes(role.to_s == "admin" ? :group_admin : :regular)
  end

  def group_membership_status_label(status)
    t("group_memberships.statuses.#{status}")
  end

  def group_membership_status_badge_classes(status)
    case status.to_s
    when "active" then "bg-emerald-100 text-emerald-800"
    when "pending" then "bg-amber-100 text-amber-900"
    when "invited" then "bg-sky-100 text-sky-900"
    else "bg-stone-100 text-stone-700"
    end
  end

  def group_membership_activity_status_label(status)
    t("group_memberships.moderation.statuses.#{status}")
  end

  def group_membership_activity_status_badge_classes(status)
    if status.to_s == "activity_suspended"
      "bg-red-50 text-red-700"
    else
      "bg-emerald-100 text-emerald-800"
    end
  end

  def group_member_ban_status_label
    t("group_member_bans.status")
  end

  def group_member_ban_status_badge_classes
    "bg-red-50 text-red-700"
  end

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
