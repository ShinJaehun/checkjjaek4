module Admin
  module ContentHelper
    include ContentPresentationHelper

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
      content_kind_badge_classes(kind)
    end

    def admin_content_status_label(status)
      content_status_label(status)
    end

    def admin_content_status_badge_classes(status)
      content_status_badge_classes(status)
    end
  end
end
