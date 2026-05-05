module BookActivitiesHelper
  def book_activity_message(activity)
    t(
      "book_activities.messages.#{activity.action}",
      user_name: activity.user.name,
      book_title: activity.book.title,
      status: book_activity_status_label(activity.metadata["to_status"]),
      sticker: book_activity_sticker_label(activity),
      summary: book_activity_update_summary(activity)
    )
  end

  def book_activity_badge_label(activity)
    case activity.action
    when "status_changed"
      book_activity_status_label(activity.metadata["to_status"])
    when "status_cleared"
      t("book_activities.badges.status_cleared")
    when "sticker_added", "sticker_removed"
      book_activity_sticker_label(activity)
    end
  end

  def book_activity_card_message(activity)
    user_link = link_to(activity.user.name, user_path(activity.user), class: "font-semibold text-stone-900 hover:text-stone-700")
    book_link = link_to(activity.book.title, book_path(activity.book), class: "font-semibold text-stone-900 hover:text-stone-700")
    badge_label = book_activity_badge_label(activity)
    badge = book_activity_badge(badge_label) if badge_label.present?

    safe_join(book_activity_message_parts(activity, user_link, book_link, badge))
  end

  private

  def book_activity_message_parts(activity, user_link, book_link, badge)
    case activity.action
    when "added_to_shelf"
      [
        user_link,
        t("book_activities.card.added_to_shelf.before_book"),
        book_link,
        t("book_activities.card.added_to_shelf.after_book")
      ]
    when "status_changed"
      [
        user_link,
        t("book_activities.card.status_changed.before_book"),
        book_link,
        t("book_activities.card.status_changed.before_status"),
        badge,
        t("book_activities.card.status_changed.after_status")
      ]
    when "status_cleared"
      [
        user_link,
        t("book_activities.card.status_cleared.before_book"),
        book_link,
        t("book_activities.card.status_cleared.before_status"),
        badge,
        t("book_activities.card.status_cleared.after_status")
      ]
    when "sticker_added", "sticker_removed"
      [
        user_link,
        t("book_activities.card.#{activity.action}.before_book"),
        book_link,
        t("book_activities.card.#{activity.action}.before_sticker"),
        badge,
        t("book_activities.card.#{activity.action}.after_sticker")
      ]
    when "bookshelf_entry_updated"
      [
        user_link,
        t("book_activities.card.bookshelf_entry_updated.before_book"),
        book_link,
        t("book_activities.card.bookshelf_entry_updated.before_summary"),
        book_activity_update_card_parts(activity),
        t("book_activities.card.bookshelf_entry_updated.after_summary")
      ].flatten
    end
  end

  def book_activity_badge(label)
    tag.span(label, class: "inline-flex rounded-full border border-stone-200 bg-stone-50 px-2 py-1 text-[0.7rem] font-medium text-stone-700")
  end

  def book_activity_status_label(status)
    return if status.blank?

    t("bookshelf_entries.statuses.#{status}")
  end

  def book_activity_sticker_label(activity)
    sticker_names = Array(activity.metadata["sticker_names"]).presence
    return sticker_names.join(", ") if sticker_names

    activity.metadata["sticker_name"]
  end

  def book_activity_update_summary(activity)
    clauses = book_activity_update_clauses(activity)
    return if clauses.empty?

    if I18n.locale.to_s.start_with?("ko")
      clauses.each_with_index.map { |clause, index| book_activity_ko_clause(clause, final: index == clauses.size - 1) }.join(", ")
    else
      clauses.each_with_index.map { |clause, index| book_activity_en_clause(clause, final: index == clauses.size - 1) }.to_sentence
    end
  end

  def book_activity_update_card_parts(activity)
    clauses = book_activity_update_card_clauses(activity)
    clauses.each_with_index.flat_map do |clause, index|
      [ (", " if index.positive?), *book_activity_update_card_clause_parts(clause, final: index == clauses.size - 1) ].compact
    end
  end

  def book_activity_update_clauses(activity)
    clauses = []
    from_status = activity.metadata["from_status"]
    to_status = activity.metadata["to_status"]

    if from_status != to_status
      clauses << { type: to_status.blank? ? :status_cleared : :status_changed, status: book_activity_status_label(to_status) }
    end

    added_stickers = Array(activity.metadata["added_sticker_names"]).reject(&:blank?)
    removed_stickers = Array(activity.metadata["removed_sticker_names"]).reject(&:blank?)
    clauses << { type: :stickers_added, stickers: added_stickers.join(", ") } if added_stickers.any?
    clauses << { type: :stickers_removed, stickers: removed_stickers.join(", ") } if removed_stickers.any?
    clauses
  end

  def book_activity_update_card_clauses(activity)
    clauses = []
    from_status = activity.metadata["from_status"]
    to_status = activity.metadata["to_status"]

    if from_status != to_status
      clauses << { type: to_status.blank? ? :status_cleared : :status_changed, status: book_activity_status_label(to_status) }
    end

    added_stickers = Array(activity.metadata["added_sticker_names"]).reject(&:blank?)
    removed_stickers = Array(activity.metadata["removed_sticker_names"]).reject(&:blank?)
    clauses << { type: :stickers_added, stickers: added_stickers } if added_stickers.any?
    clauses << { type: :stickers_removed, stickers: removed_stickers } if removed_stickers.any?
    clauses
  end

  def book_activity_update_card_clause_parts(clause, final:)
    if I18n.locale.to_s.start_with?("ko")
      book_activity_ko_card_clause_parts(clause, final: final)
    else
      book_activity_en_card_clause_parts(clause, final: final)
    end
  end

  def book_activity_ko_card_clause_parts(clause, final:)
    case clause[:type]
    when :status_changed
      [ "상태를 ", book_activity_badge(clause[:status]), korean_direction_particle(clause[:status]), final ? " 바꿨습니다." : " 바꿨고" ]
    when :status_cleared
      [ final ? "독서 상태를 비웠습니다." : "독서 상태를 비웠고" ]
    when :stickers_added
      [ *book_activity_badges(clause[:stickers]), final ? " 스티커를 붙였습니다." : " 스티커를 붙였고" ]
    when :stickers_removed
      [ *book_activity_badges(clause[:stickers]), final ? " 스티커를 제거했습니다." : " 스티커를 제거했고" ]
    end
  end

  def book_activity_en_card_clause_parts(clause, final:)
    case clause[:type]
    when :status_changed
      [ "changed status to ", book_activity_badge(clause[:status]) ]
    when :status_cleared
      [ "cleared the reading status" ]
    when :stickers_added
      [ "added ", *book_activity_badges(clause[:stickers]), " sticker(s)" ]
    when :stickers_removed
      [ "removed ", *book_activity_badges(clause[:stickers]), " sticker(s)" ]
    end
  end

  def book_activity_badges(labels)
    labels.each_with_index.flat_map do |label, index|
      [ (index.positive? ? " " : nil), book_activity_badge(label) ].compact
    end
  end

  def book_activity_ko_clause(clause, final:)
    key_suffix = final ? "final" : "connector"

    case clause[:type]
    when :status_changed
      t("book_activities.update_clauses.ko.status_changed.#{key_suffix}", status: clause[:status], particle: korean_direction_particle(clause[:status]))
    when :status_cleared
      t("book_activities.update_clauses.ko.status_cleared.#{key_suffix}")
    when :stickers_added
      t("book_activities.update_clauses.ko.stickers_added.#{key_suffix}", stickers: clause[:stickers])
    when :stickers_removed
      t("book_activities.update_clauses.ko.stickers_removed.#{key_suffix}", stickers: clause[:stickers])
    end
  end

  def book_activity_en_clause(clause, final:)
    key_suffix = final ? "final" : "connector"

    case clause[:type]
    when :status_changed
      t("book_activities.update_clauses.en.status_changed.#{key_suffix}", status: clause[:status])
    when :status_cleared
      t("book_activities.update_clauses.en.status_cleared.#{key_suffix}")
    when :stickers_added
      t("book_activities.update_clauses.en.stickers_added.#{key_suffix}", stickers: clause[:stickers])
    when :stickers_removed
      t("book_activities.update_clauses.en.stickers_removed.#{key_suffix}", stickers: clause[:stickers])
    end
  end

  def korean_direction_particle(text)
    last_codepoint = text.to_s.each_codepoint.to_a.last
    return "로" unless last_codepoint&.between?(0xAC00, 0xD7A3)

    jongseong = (last_codepoint - 0xAC00) % 28
    jongseong.zero? || jongseong == 8 ? "로" : "으로"
  end
end
