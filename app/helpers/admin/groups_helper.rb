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

    def admin_group_type_badge_classes(group)
      case group.group_type
      when "public_group"
        "bg-sky-100 text-sky-800"
      when "approval_group"
        "bg-amber-100 text-amber-900"
      when "private_group"
        "bg-violet-100 text-violet-800"
      else
        "bg-stone-100 text-stone-700"
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
