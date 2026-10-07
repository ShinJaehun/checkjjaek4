module ContentPresentationHelper
  def content_kind_badge_classes(kind)
    case kind.to_s
    when "general", "group_general" then "bg-sky-100 text-sky-800"
    when "book", "group_book" then "bg-emerald-100 text-emerald-800"
    when "requote" then "bg-violet-100 text-violet-800"
    when "comments" then "bg-amber-100 text-amber-900"
    else "bg-stone-100 text-stone-700"
    end
  end

  def content_status_badge_classes(status)
    case status.to_s
    when "active" then "bg-emerald-100 text-emerald-800"
    when "hidden" then "bg-red-100 text-red-800"
    else "bg-stone-200 text-stone-700"
    end
  end

  def content_status_label(status)
    t("content_statuses.#{status}")
  end

  def content_status_badge(status)
    content_tag :span, content_status_label(status),
                class: "rounded-full px-2 py-1 text-xs #{content_status_badge_classes(status)}"
  end
end
