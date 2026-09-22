module Admin
  module GroupsHelper
    def admin_group_history_entries(lifecycle_events, operation_actions)
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
  end
end
