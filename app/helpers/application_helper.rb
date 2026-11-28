module ApplicationHelper
  def user_validation_error_message(error)
    if I18n.locale == :ko && error.attribute == :handle && error.type == :taken
      error.message
    else
      error.full_message
    end
  end

  def validation_error_aria(form, attribute, describedby: [])
    error_ids = form.object.errors.where(attribute).each_index.map { |index| validation_error_id(form, attribute, index) }
    descriptions = [ *describedby, *error_ids ].compact

    { invalid: (true if error_ids.any?), describedby: (descriptions.join(" ") if descriptions.any?) }.compact
  end

  def validation_error_messages(form)
    form.object.errors.group_by_attribute.flat_map do |attribute, errors|
      errors.map.with_index do |error, index|
        tag.span(yield(error), id: validation_error_id(form, attribute, index))
      end
    end
  end

  def validation_error_id(form, attribute, index)
    return form.field_id(attribute, :errors) if index.zero?

    form.field_id(attribute, :errors, index + 1)
  end

  def form_error_messages(messages, **attributes)
    return if messages.empty?
    return tag.p(messages.first, **attributes) if messages.one?

    attributes[:class] = class_names(attributes[:class], "list-disc pl-5")
    tag.ul(safe_join(messages.map { |message| tag.li(message) }), **attributes)
  end

  def unread_notifications_count
    return 0 unless user_signed_in?

    @unread_notifications_count ||= current_user.received_notifications.unread.count
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
      [ entry[:occurred_at], entry[:kind] == :lifecycle ? 0 : 1, entry[:sort_id] ]
    end.reverse
  end

  def group_history_actor_label(record)
    return t("groups.lifecycle_history.actor.unknown") unless record.actor

    role = case record
    when GroupLifecycleEvent
      case record.event_type
      when "opening_approved", "opening_rejected", "reactivation_approved", "reactivation_rejected"
        :system_admin
      when "opening_requested", "opening_cancelled", "operations_closed", "reactivation_requested", "reactivation_withdrawn"
        :group_admin
      end
    when ModerationAction
      :system_admin if record.action_type.in?(%w[suspend_group_operation restore_group_operation])
    end
    return record.actor.name unless role

    t(
      "groups.lifecycle_history.actor.label",
      role: t("groups.lifecycle_history.actor.roles.#{role}"),
      name: record.actor.name
    )
  end
end
