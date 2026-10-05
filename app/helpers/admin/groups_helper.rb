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

    def admin_group_activity_badge_classes(kind)
      case kind.to_s
      when "general", "group_general"
        "bg-sky-100 text-sky-800"
      when "book", "group_book"
        "bg-emerald-100 text-emerald-800"
      when "requote"
        "bg-violet-100 text-violet-800"
      when "comments"
        "bg-amber-100 text-amber-900"
      else
        "bg-stone-100 text-stone-700"
      end
    end
  end
end
