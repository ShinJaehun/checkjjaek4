module Admin
  module ContentHelper
    include ContentPresentationHelper

    CONTENT_BADGE_CLASSES = {
      "general" => "bg-sky-100 text-sky-800",
      "group_general" => "bg-emerald-100 text-emerald-800",
      "requote" => "bg-violet-100 text-violet-800",
      "comments" => "bg-amber-100 text-amber-900"
    }.freeze

    def admin_content_kind_key(kind, context: nil)
      return "comments" if kind.is_a?(Comment)
      if kind.is_a?(Jjaek)
        return "requote" if kind.requote?

        return kind.group_id.present? ? "group_general" : "general"
      end
      return "comments" if kind.to_s == "comments"
      return "requote" if kind.to_s == "requote"
      return "group_general" if context == :group || kind.to_s.in?(%w[group group_general])

      "general"
    end

    def admin_content_kind_label(kind, context: nil)
      admin_content_badge(kind, context:).fetch(:label)
    end

    def admin_content_badge(kind, context: nil)
      key = admin_content_kind_key(kind, context:)
      { kind: key, label: t("admin.user_content.kinds.#{key}"), classes: CONTENT_BADGE_CLASSES.fetch(key) }
    end

    def admin_content_sources(records)
      source_ids = records.filter_map do |record|
        next if record.is_a?(Jjaek) && record.deleted?

        record.is_a?(Comment) ? record.jjaek_id : record.quoted_jjaek_id
      end.uniq
      return {} if source_ids.empty?

      JjaekPolicy::AdminInventoryScope.new(current_user, Jjaek).resolve
        .where(id: source_ids, deleted_at: nil).includes(:user).index_by(&:id)
    end

    def admin_content_metadata(record, sources:)
      return [] if record.is_a?(Jjaek) && record.deleted?

      metadata = []
      if record.is_a?(Jjaek)
        books = record.attached_books.to_a
        if books.one?
          metadata << books.first.title
        elsif books.many?
          metadata << t("admin.user_content.metadata.multiple_books", title: books.first.title, count: books.size - 1)
        end
      end
      source_id = record.is_a?(Comment) ? record.jjaek_id : record.quoted_jjaek_id
      if (source = sources[source_id])
        excerpt = truncate(source.content.to_s.squish, length: 140, omission: " [...]").presence || "-"
        metadata << t("admin.user_content.metadata.source", author: source.user.name, content: excerpt)
      end
      metadata
    end

    def admin_content_status_label(status)
      content_status_label(status)
    end

    def admin_content_status_badge_classes(status)
      content_status_badge_classes(status)
    end

    def admin_content_status(record, record_type:)
      return :deleted if record_type == "Jjaek" && record.deleted?
      return :hidden if record.hidden?

      :active
    end

    def admin_content_body(record, record_type:)
      return "-" if record_type == "Jjaek" && record.deleted?

      truncate(record.content.to_s, length: 140, omission: " [...]").presence || "-"
    end
  end
end
