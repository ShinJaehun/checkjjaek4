module ApplicationHelper
  def unread_notifications_count
    return 0 unless user_signed_in?

    @unread_notifications_count ||= current_user.received_notifications.unread.count
  end

  def show_notification_badge?
    unread_notifications_count.positive?
  end

  def group_lifecycle_stages(events)
    events.each_with_object([]) do |event, stages|
      case event.event_type
      when "opening_requested"
        stages << { type: :opening, requested: event }
      when "opening_approved"
        stage = stages.reverse_each.find { |item| item[:type] == :opening && !item[:approved] }
        stage ? stage.store(:approved, event) : stages << { type: :opening, approved: event }
      when "operations_closed"
        stages << { type: :closure, event: event }
      when "reactivation_requested"
        stages << { type: :reactivation, requested: event }
      when "reactivation_approved"
        stage = stages.reverse_each.find { |item| item[:type] == :reactivation && !item[:approved] }
        stage ? stage.store(:approved, event) : stages << { type: :reactivation, approved: event }
      end
    end
  end

  def group_history_entries(lifecycle_events, operation_actions)
    lifecycle_entries = group_lifecycle_stages(lifecycle_events).map do |stage|
      first_event = case stage[:type]
                    when :opening, :reactivation
                      stage[:requested] || stage.fetch(:approved)
                    when :closure
                      stage.fetch(:event)
                    end

      { type: :lifecycle, occurred_at: first_event.created_at, sort_id: first_event.id, stage: }
    end

    platform_entries = operation_actions.map do |action|
      { type: :platform, occurred_at: action.created_at, sort_id: action.id, action: }
    end

    (lifecycle_entries + platform_entries).sort_by do |entry|
      [ entry[:occurred_at], entry[:type] == :lifecycle ? 0 : 1, entry[:sort_id] ]
    end
  end

  def group_history_entries(lifecycle_events:, moderation_actions:)
    lifecycle_entries = lifecycle_events.map do |event|
      {
        kind: :lifecycle,
        record: event,
        occurred_at: event.created_at,
        sort_id: event.id
      }
    end

    moderation_entries = moderation_actions.map do |action|
      {
        kind: :platform,
        record: action,
        occurred_at: action.created_at,
        sort_id: action.id
      }
    end

    (lifecycle_entries + moderation_entries).sort_by do |entry|
      [entry[:occurred_at], entry[:kind] == :lifecycle ? 0 : 1, entry[:sort_id]]
    end
  end

  def group_history_actor_label(record)
    return t("groups.lifecycle_history.actor.unknown") unless record.actor

    role = record.actor.global_admin? ? :system_admin : :group_admin

    t(
      "groups.lifecycle_history.actor.label",
      role: t("groups.lifecycle_history.actor.roles.#{role}"),
      name: record.actor.name
    )
  end
end
