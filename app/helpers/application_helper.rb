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
end
