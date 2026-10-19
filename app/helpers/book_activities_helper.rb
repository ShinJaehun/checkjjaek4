module BookActivitiesHelper
  def book_activity_card_message(activity, context: :feed, sticker_definitions: {})
    user_link = link_to(activity.user.name, user_path(activity.user), class: "font-semibold text-stone-900 hover:text-stone-700")
    if activity.added_to_shelf?
      return safe_join([ user_link, t("book_activities.card_copy.added_to_shelf.#{context}") ])
    end

    clauses = book_activity_change_clauses(activity, sticker_definitions)
    if clauses.empty?
      return safe_join([ user_link, t("book_activities.card_copy.changed.#{context}") ])
    end

    parts = clauses.each_with_index.flat_map do |clause, index|
      [ (", " if index.positive?), *book_activity_clause_parts(clause, final: index == clauses.size - 1) ].compact
    end
    safe_join([ user_link, t("book_activities.card_copy.change_prefix.#{context}"), *parts, ("." unless I18n.locale.to_s.start_with?("ko")) ])
  end

  private

  def book_activity_change_clauses(activity, sticker_definitions)
    metadata = activity.metadata
    clauses = []

    if activity.status_changed? || (activity.bookshelf_entry_updated? && metadata["from_status"] != metadata["to_status"])
      status = metadata["to_status"]
      clauses << { type: :status_changed, badge: reading_status_badge(status), label: reading_status_label(status) } if status.present?
    end
    if activity.status_cleared? || (activity.bookshelf_entry_updated? && metadata["from_status"] != metadata["to_status"] && metadata["to_status"].blank?)
      clauses << { type: :status_cleared }
    end

    if activity.bookshelf_entry_updated?
      book_activity_add_sticker_clause(clauses, :stickers_added, metadata["added_sticker_definition_ids"], metadata["added_sticker_names"], sticker_definitions)
      book_activity_add_sticker_clause(clauses, :stickers_removed, metadata["removed_sticker_definition_ids"], metadata["removed_sticker_names"], sticker_definitions)
    elsif activity.sticker_added? || activity.sticker_removed?
      ids = metadata["sticker_definition_ids"] || metadata["sticker_definition_id"]
      names = metadata["sticker_names"] || metadata["sticker_name"]
      type = activity.sticker_added? ? :stickers_added : :stickers_removed
      book_activity_add_sticker_clause(clauses, type, ids, names, sticker_definitions)
    end
    clauses
  end

  def book_activity_add_sticker_clause(clauses, type, ids, names, sticker_definitions)
    ids = Array(ids).reject(&:blank?)
    names = Array(names).reject(&:blank?)
    badges = Array.new([ ids.size, names.size ].max) do |index|
      sticker = sticker_definitions[ids[index].to_i] if ids[index]
      sticker ? reading_sticker_badge(sticker) : book_activity_legacy_sticker_badge(names[index])
    end.compact
    clauses << { type:, badges: } if badges.any?
  end

  def book_activity_legacy_sticker_badge(name)
    return if name.blank?

    tag.span(name, class: "inline-flex rounded-full border border-stone-200 bg-stone-50 px-2 py-1 text-[0.7rem] font-medium text-stone-700")
  end

  def book_activity_clause_parts(clause, final:)
    return book_activity_ko_clause_parts(clause, final:) if I18n.locale.to_s.start_with?("ko")

    case clause[:type]
    when :status_changed then [ "changed the reading status to ", clause[:badge] ]
    when :status_cleared then [ "cleared the reading status" ]
    when :stickers_added then [ "added ", safe_join(clause[:badges], ", "), " sticker(s)" ]
    when :stickers_removed then [ "removed ", safe_join(clause[:badges], ", "), " sticker(s)" ]
    end
  end

  def book_activity_ko_clause_parts(clause, final:)
    case clause[:type]
    when :status_changed
      [ "상태를 ", clause[:badge], korean_direction_particle(clause[:label]), final ? " 바꿨습니다." : " 바꿨고" ]
    when :status_cleared
      [ final ? "독서 상태를 비웠습니다." : "독서 상태를 비웠고" ]
    when :stickers_added
      [ safe_join(clause[:badges], ", "), final ? " 스티커를 붙였습니다." : " 스티커를 붙였고" ]
    when :stickers_removed
      [ safe_join(clause[:badges], ", "), final ? " 스티커를 제거했습니다." : " 스티커를 제거했고" ]
    end
  end

  def korean_direction_particle(text)
    last_codepoint = text.to_s.each_codepoint.to_a.last
    return "로" unless last_codepoint&.between?(0xAC00, 0xD7A3)

    jongseong = (last_codepoint - 0xAC00) % 28
    jongseong.zero? || jongseong == 8 ? "로" : "으로"
  end
end
