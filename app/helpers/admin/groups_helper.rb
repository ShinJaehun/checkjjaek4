module Admin
  module GroupsHelper
    GROUP_STATUS_FILTERS = %w[
      pending_approval
      active
      inactive
      reactivation_pending
      suspended
    ].freeze

    def admin_group_current_status_key(group)
      return :suspended if group.operation_suspended?
      return :reactivation_pending if group.pending_approval? && group.closed_at.present?

      group.lifecycle_status.to_sym
    end

    def admin_group_current_status(group)
      t("admin.groups.current_statuses.#{admin_group_current_status_key(group)}")
    end

    def admin_group_status_filter_options
      GROUP_STATUS_FILTERS.map do |status|
        [t("admin.groups.current_statuses.#{status}"), status]
      end
    end

    def admin_group_status_badge_classes(group)
      case admin_group_current_status_key(group)
      when :pending_approval, :reactivation_pending
        "bg-amber-100 text-amber-900"
      when :suspended
        "bg-red-50 text-red-700"
      when :inactive
        "bg-stone-200 text-stone-700"
      else
        "bg-stone-100 text-stone-700"
      end
    end
  end
end
