module GroupsHelper
  def group_type_label(group)
    t("groups.types.#{group.group_type}")
  end

  def group_type_badge_classes(group)
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

  def group_current_status_key(group)
    return :suspended if group.operation_suspended?
    return :reactivation_pending if group.pending_approval? && group.closed_at.present?

    group.lifecycle_status.to_sym
  end

  def group_current_status_label(group)
    t("groups.current_statuses.#{group_current_status_key(group)}")
  end

  def group_status_badge_classes(group)
    case group_current_status_key(group)
    when :active
      "bg-emerald-100 text-emerald-800"
    when :pending_approval, :reactivation_pending
      "bg-amber-100 text-amber-900"
    when :suspended
      "bg-red-50 text-red-700"
    else
      "bg-stone-200 text-stone-700"
    end
  end
end
