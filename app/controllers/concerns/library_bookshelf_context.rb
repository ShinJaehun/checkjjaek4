module LibraryBookshelfContext
  extend ActiveSupport::Concern

  private

  def prepare_library_bookshelf(selected_bookshelf_id: params[:bookshelf_id], new_bookshelf: nil, managed_bookshelf: nil, show_notes: false)
    profile_policy = policy(@user)
    owner = current_user == @user
    @library_notes_page_number = Integer(params[:notes_page], exception: false) if owner
    prepare_library_book_notes if owner && show_notes
    @show_bookshelf = profile_policy.show_profile_bookshelf?
    @show_profile_bookshelf_status = profile_policy.show_profile_bookshelf_status?
    @show_profile_bookshelf_move_control = owner
    @show_profile_bookshelf_create_form = owner
    @profile_bookshelf_sort = library_bookshelf_sort
    @profile_bookshelf_sort_options = BookshelfEntry::PROFILE_SORTS

    return unless @show_bookshelf

    @profile_bookshelves = policy_scope(@user.bookshelves, policy_scope_class: BookshelfPolicy::LibraryScope).default_first
    visible_entries = policy_scope(@user.bookshelf_entries, policy_scope_class: BookshelfEntryPolicy::ProfileScope)
      .where(bookshelf: @profile_bookshelves)
    @profile_bookshelf_entry_counts = visible_entries.group(:bookshelf_id).count
    summary_bookshelves = if owner
      @profile_bookshelves.to_a
    else
      @profile_bookshelves.reject(&:visibility_private?)
    end
    @library_bookshelf_count = summary_bookshelves.size
    @library_book_count = summary_bookshelves.sum do |bookshelf|
      @profile_bookshelf_entry_counts.fetch(bookshelf.id, 0)
    end
    @selected_bookshelf = selected_library_bookshelf(@profile_bookshelves, selected_bookshelf_id)
    return if @library_book_note_page

    @bookshelf = new_bookshelf || @user.bookshelves.build(visibility: :public, color_key: "stone") if owner
    @profile_bookshelf_visibility_options = Bookshelf.visibilities.keys
    @profile_bookshelf_color_options = Bookshelf::COLOR_KEYS
    @managed_bookshelf = managed_bookshelf || @selected_bookshelf if owner && @selected_bookshelf&.is_default? == false
    @profile_bookshelf_order_controls = owner ? bookshelf_order_controls(@profile_bookshelves) : {}
    @bookshelf_entries =
      if @selected_bookshelf
        visible_entries.where(bookshelf: @selected_bookshelf).profile_sorted(@profile_bookshelf_sort)
      else
        BookshelfEntry.none
      end
  end

  def prepare_library_book_notes
    notes = policy_scope(BookNote).recent_first.with_rich_text_body.includes(user_book: :book)
    @library_book_note_page = Admin::InventoryPage.new(notes, page: @library_notes_page_number)
    @library_notes_page_number = @library_book_note_page.page
    no_store
  end

  def library_bookshelf_sort
    return params[:sort] if BookshelfEntry::PROFILE_SORTS.include?(params[:sort])

    current_user == @user ? "manual" : "recent"
  end

  def selected_library_bookshelf(accessible_bookshelves, bookshelf_id)
    bookshelves = accessible_bookshelves.to_a
    requested_bookshelf = bookshelves.find { |bookshelf| bookshelf.id.to_s == bookshelf_id.to_s }

    requested_bookshelf || bookshelves.find(&:is_default?) || bookshelves.first
  end

  def bookshelf_order_controls(bookshelves)
    regular_bookshelves = bookshelves.reject(&:is_default?)
    regular_bookshelves.each_with_index.to_h do |bookshelf, index|
      [ bookshelf.id, { move_up: index.positive?, move_down: index < regular_bookshelves.size - 1 } ]
    end
  end
end
