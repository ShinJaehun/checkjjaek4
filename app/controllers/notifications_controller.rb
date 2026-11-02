class NotificationsController < ApplicationController
  def index
    authorize Notification
    @notifications = policy_scope(Notification).includes(:notifiable, actor: { avatar_attachment: :blob }).recent.to_a
    @unread_notification_ids = @notifications.filter_map { |notification| notification.id if notification.unread? }
    mark_notifications_as_read
    prepare_notification_display_data
  end

  private

  def prepare_notification_display_data
    # Only the read-only display phase reuses policy results; read-state mutations are already complete.
    @notification_policy_results = {}
    notifiables = @notifications.filter_map(&:notifiable)
    events = notifiables.grep(GroupLifecycleEvent) + notifiables.grep(GroupMembershipEvent)
    preload_notification_associations(events, :group)

    actions = notifiables.grep(ModerationAction)
    targeted_actions = actions.select { |action| action.target_type.in?(%w[Group Jjaek Comment]) }
    preload_notification_associations(targeted_actions, :target)
    targets = targeted_actions.filter_map(&:target)

    comments = notifiables.grep(Comment) + targets.grep(Comment)
    preload_notification_associations(comments, :jjaek)
    jjaeks = notifiables.grep(Jjaek) + targets.grep(Jjaek) + comments.filter_map(&:jjaek)
    preload_notification_associations(jjaeks, [ :group, :quoted_jjaek ])
    sources = jjaeks.filter_map(&:quoted_jjaek)
    preload_notification_associations(sources, :group)
    friend_posts = (jjaeks + sources).select { |jjaek| jjaek.group_id.nil? && jjaek.book_friends? }
    preload_notification_associations(friend_posts, :user)

    group_ids = actions.select { |action| action.target_type.in?(%w[GroupMembership GroupMemberBan]) }
      .filter_map(&:membership_group_id).uniq
    groups = Group.where(id: group_ids).index_by(&:id)
    @notification_membership_groups_by_id = group_ids.to_h { |id| [ id, groups[id] ] }
  end

  def preload_notification_associations(records, associations)
    return if records.empty?

    ActiveRecord::Associations::Preloader.new(records:, associations:).call
  end

  def mark_notifications_as_read
    return if @unread_notification_ids.empty?

    unread_notifications = current_user.received_notifications.unread.where(id: @unread_notification_ids)
    updated_count = unread_notifications.update_all(read_at: Time.current, updated_at: Time.current)
    Notification.broadcast_badge_to(current_user) if updated_count.positive?
  end
end
