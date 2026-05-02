module BookActivitiesHelper
  def book_activity_message(activity)
    t(
      "book_activities.messages.#{activity.action}",
      user_name: activity.user.name,
      book_title: activity.book.title,
      status: book_activity_status_label(activity.metadata["to_status"]),
      sticker: activity.metadata["sticker_name"]
    )
  end

  def book_activity_badge_label(activity)
    case activity.action
    when "status_changed"
      book_activity_status_label(activity.metadata["to_status"])
    when "status_cleared"
      t("book_activities.badges.status_cleared")
    when "sticker_added", "sticker_removed"
      activity.metadata["sticker_name"]
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
    end
  end

  def book_activity_badge(label)
    tag.span(label, class: "inline-flex rounded-full border border-stone-200 bg-stone-50 px-2 py-1 text-[0.7rem] font-medium text-stone-700")
  end

  def book_activity_status_label(status)
    return if status.blank?

    t("bookshelf_entries.statuses.#{status}")
  end
end
