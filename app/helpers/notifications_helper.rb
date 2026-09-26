module NotificationsHelper
  def notification_message(notification)
    return moderation_notification_message(notification) if notification.moderation?
    return group_lifecycle_notification_message(notification) if notification.group_lifecycle?
    return group_membership_notification_message(notification) if notification.group_membership_workflow?

    if notification.comment_created? && notification.notifiable&.jjaek&.group.present?
      return t(
        "notifications.messages.group_comment_created",
        actor_name: notification.actor.name,
        group_name: notification.notifiable.jjaek.group.name
      )
    end

    t("notifications.messages.#{notification.action}", actor_name: notification.actor.name)
  end

  def notification_target_path(notification)
    return moderation_notification_target_path(notification) if notification.moderation?
    return group_lifecycle_notification_target_path(notification) if notification.group_lifecycle?
    return group_membership_notification_target_path(notification) if notification.group_membership_workflow?

    case notification.action
    when "book_friendship_requested"
      relationships_path(anchor: "received-book-friend-requests")
    when "profile_jjaek_created", "requote_created"
      notification.notifiable ? jjaek_path(notification.notifiable) : root_path
    when "comment_created"
      notification.notifiable ? jjaek_path(notification.notifiable.jjaek) : root_path
    else
      root_path
    end
  end

  private

  def group_membership_notification_message(notification)
    event = notification.notifiable
    return t("notifications.membership.unavailable") unless event

    group_name = event.group&.name || t("notifications.membership.group_fallback")
    options = { group_name: }
    options[:actor_name] = notification.actor.name if notification.group_membership_requested_to_join?
    t("notifications.messages.#{notification.action}", **options)
  end

  def group_membership_notification_target_path(notification)
    group = notification.notifiable&.group
    return groups_path unless group

    if notification.group_membership_requested_to_join?
      current_admin = group.group_admin?(current_user)
      can_view_members = GroupPolicy.new(current_user, group).view_members?
      current_admin && can_view_members ? group_members_path(group) : groups_path
    else
      readable_group_path_or_fallback(group)
    end
  end

  def group_lifecycle_notification_message(notification)
    event = notification.notifiable
    return t("notifications.lifecycle.unavailable") unless event

    group_name = event.group&.name || t("notifications.lifecycle.group_fallback")
    t("notifications.messages.#{notification.action}", group_name:)
  end

  def group_lifecycle_notification_target_path(notification)
    group = notification.notifiable&.group
    return groups_path unless group

    if notification.group_opening_requested? || notification.group_reactivation_requested?
      GroupPolicy.new(current_user, group).view_admin_details? ? admin_group_path(group) : groups_path
    else
      readable_group_path_or_fallback(group)
    end
  end

  def moderation_notification_message(notification)
    action = notification.notifiable
    return t("notifications.moderation.unavailable") unless action

    authority = moderation_notification_authority(action)
    options = {
      authority: t("notifications.authorities.#{authority}"),
      reason: moderation_notification_reason(action)
    }
    options[:group_name] = action.target&.name || t("notifications.moderation.group_fallback") if action.target_type == "Group"
    if action.target_type == "GroupMembership"
      options[:group_name] = Group.find_by(id: action.membership_group_id)&.name || t("notifications.moderation.group_fallback")
    end

    t("notifications.messages.#{notification.action}", **options)
  end

  def moderation_notification_authority(action)
    return "group" if action.target_type == "GroupMembership"

    action.group_authority? ? "group" : "platform"
  end

  def moderation_notification_reason(action)
    case action.target_type
    when "User"
      User.suspension_reason_label(action.public_reason)
    when "Group"
      Group.suspension_reason_label(action.public_reason)
    when "GroupMembership"
      action.public_reason
    when "Jjaek", "Comment"
      action.action_type_hide? ? jjaek_hide_reason_label(action.public_reason) : action.public_reason
    end
  end

  def moderation_notification_target_path(notification)
    action = notification.notifiable
    return user_path(current_user) unless action

    target = action.target
    case action.target_type
    when "User"
      user_path(current_user)
    when "Group"
      readable_group_path_or_fallback(target)
    when "GroupMembership"
      readable_group_path_or_fallback(Group.find_by(id: action.membership_group_id))
    when "Jjaek"
      readable_jjaek_path_or_fallback(target)
    when "Comment"
      readable_jjaek_path_or_fallback(target&.jjaek, comment: target)
    else
      user_path(current_user)
    end
  end

  def readable_group_path_or_fallback(group)
    group && GroupPolicy.new(current_user, group).show? ? group_path(group) : groups_path
  end

  def readable_jjaek_path_or_fallback(jjaek, comment: nil)
    return user_path(current_user) unless jjaek
    if JjaekPolicy.new(current_user, jjaek).show?
      return comment ? jjaek_path(jjaek, anchor: dom_id(comment)) : jjaek_path(jjaek)
    end

    group = jjaek.group
    return user_path(current_user) unless group

    GroupPolicy.new(current_user, group).show? ? group_path(group) : groups_path
  end
end
