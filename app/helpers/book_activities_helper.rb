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

  private

  def book_activity_status_label(status)
    return if status.blank?

    t("bookshelf_entries.statuses.#{status}")
  end
end
