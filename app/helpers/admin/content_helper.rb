module Admin
  module ContentHelper
    def admin_content_kind_key(kind, context: nil)
      return "group_general" if context == :group && kind.to_s == "general"
      return "group_book" if context == :group && kind.to_s == "book"

      kind.to_s
    end

    def admin_content_kind_label(kind, context: nil)
      key = admin_content_kind_key(kind, context:)
      t("admin.user_content.kinds.#{key}", default: key)
    end

    def admin_content_kind_badge_classes(kind)
      case kind.to_s
      when "general", "group_general" then "bg-sky-100 text-sky-800"
      when "book", "group_book" then "bg-emerald-100 text-emerald-800"
      when "requote" then "bg-violet-100 text-violet-800"
      when "comments" then "bg-amber-100 text-amber-900"
      else "bg-stone-100 text-stone-700"
      end
    end

    def admin_content_status_label(status)
      t("admin.user_content.statuses.#{status}")
    end

    def admin_content_status_badge_classes(status)
      case status.to_s
      when "hidden" then "bg-red-100 text-red-800"
      else "bg-stone-200 text-stone-700"
      end
    end
  end
end
