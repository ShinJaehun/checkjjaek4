module BookShowContext
  private

  # Callers prepare @book and the form context (@bookshelf_entry, @jjaek,
  # @group and @quoted_jjaek) before preparing the full page.
  def prepare_book_show_read_context(feed_only: false)
    prepare_book_show_form_context unless feed_only
    return @jjaeks = Jjaek.none unless @book.persisted?

    prepare_book_notes unless feed_only
    book_jjaeks = @book.attached_jjaeks
      .includes(:attached_books, :group, user: { avatar_attachment: :blob }, target_user: { avatar_attachment: :blob })
    @jjaeks = if @group.present?
      policy_scope(book_jjaeks, policy_scope_class: JjaekPolicy::GroupContentScope).where(group: @group)
    else
      policy_scope(book_jjaeks, policy_scope_class: JjaekPolicy::BookScope)
    end
    @feed_page = FeedPage.new(jjaeks: @jjaeks.where(quoted_jjaek_id: nil), cursor: params[:cursor])
    if @feed_page.next_cursor
      @feed_next_url = book_path(@book, group_id: @group&.id,
        return_to: view_context.validated_jjaek_return_path(params[:return_to]), cursor: @feed_page.next_cursor, tab: "jjaeks")
    end
    @jjaeks = @feed_page.items
    prepare_current_reading_states_for(@jjaeks)
    prepare_book_friend_activities unless feed_only
    card_jjaeks = @jjaeks + Array(@book_friend_activities).grep(Jjaek)
    prepare_jjaek_card_summaries_for(card_jjaeks)
    prepare_visible_requote_counts_for(card_jjaeks)
    prepare_group_share_destinations_for(card_jjaeks)
  end

  def prepare_book_show_form_context
    @bookshelves = current_user.bookshelves.default_first
    @can_write_book_jjaek = @jjaek.present? && policy(@jjaek).create?
    @book_return_path = view_context.validated_jjaek_return_path(params[:return_to])
    @book_detail_tab = book_detail_tab if @bookshelf_entry
  end

  def book_detail_tab
    return "jjaeks" if @book_jjaek_form_open
    return "reading" if @bookshelf_entry.errors.any? || @new_book_note&.errors&.any?
    return params[:tab] if params[:tab].in?(%w[reading jjaeks])
    return "jjaeks" if params[:cursor].present? || @group.present?
    return "reading" if params[:notes_page].present?
    return "reading" if @book_return_path && URI.parse(@book_return_path).path == user_library_path(current_user)

    "jjaeks"
  end

  def prepare_book_notes
    return if @group.present?

    user_book = @bookshelf_entry&.user_book || current_user.user_books.find_by(book: @book)
    return unless user_book

    @book_note_return_path = @book_return_path
    return if @new_book_note.nil? && foreign_bookshelf_book?(@book_note_return_path)

    notes = policy_scope(user_book.book_notes).recent_first.with_rich_text_body
    @book_note_page = Admin::InventoryPage.new(notes, page: params[:notes_page])
    @new_book_note ||= user_book.book_notes.build if @bookshelf_entry
    no_store if @new_book_note || @book_note_page.total_count.positive?
  end

  def foreign_bookshelf_book?(return_path)
    return false unless return_path

    route = Rails.application.routes.recognize_path(URI.parse(return_path).path, method: :get)
    case route[:controller]
    when "users/libraries"
      route[:user_id] != current_user.to_param
    when "users"
      route[:action] == "show" && route[:id] != current_user.to_param
    end
  end

  def prepare_book_friend_activities
    friend_ids = BookFriendship.connected_ids_for(current_user)
    activities = policy_scope(BookActivity.where(book: @book), policy_scope_class: BookActivityPolicy::BookFriendScope)
      .includes(:book, user: { avatar_attachment: :blob })
      .order(created_at: :desc, id: :desc)
      .limit(3)
      .to_a
    jjaeks = policy_scope(
      @book.attached_jjaeks.where(user_id: friend_ids, group_id: nil, hidden_at: nil, deleted_at: nil),
      policy_scope_class: JjaekPolicy::BookScope
    ).includes(:attached_books, user: { avatar_attachment: :blob },
      quoted_jjaek: [ { user: { avatar_attachment: :blob } }, :attached_books, :group ])
      .order(created_at: :desc, id: :desc).limit(3).to_a

    @book_friend_activities = (activities + jjaeks)
      .sort_by { |item| [ -item.created_at.to_r, item.is_a?(BookActivity) ? 0 : 1, -item.id ] }
      .first(3)

    sticker_ids = @book_friend_activities.grep(BookActivity).flat_map do |activity|
      metadata = activity.metadata
      Array(metadata["added_sticker_definition_ids"]) + Array(metadata["removed_sticker_definition_ids"]) +
        Array(metadata["sticker_definition_ids"]) + Array(metadata["sticker_definition_id"])
    end
    @book_friend_sticker_definitions = sticker_ids.empty? ? {} : StickerDefinition.where(id: sticker_ids).index_by(&:id)
  end
end
