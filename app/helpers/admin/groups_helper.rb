module Admin
  module GroupsHelper
    GROUP_STATUS_FILTERS = %w[
      pending_approval
      active
      inactive
      reactivation_pending
      suspended
    ].freeze

    def admin_group_status_filter_options
      GROUP_STATUS_FILTERS.map do |status|
        [t("groups.current_statuses.#{status}"), status]
      end
    end
  end
end
