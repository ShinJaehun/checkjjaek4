module Groups
  module ContentsHelper
    include ContentPresentationHelper

    def group_content_status(record)
      return :deleted if record.is_a?(Jjaek) && record.deleted?
      return :hidden if record.hidden?

      :active
    end

    def group_content_body_visible?(record)
      return false if group_content_status(record) == :deleted
      return true unless record.hidden?

      record.current_hide_action&.group_authority? || false
    end

    def group_content_body(record, visible:)
      return truncate(record.content.to_s, length: 140, omission: " [...]").presence || "-" if visible
      return t("groups.content_inventory.tombstones.deleted") if group_content_status(record) == :deleted

      t("groups.content_inventory.tombstones.platform_hidden")
    end
  end
end
