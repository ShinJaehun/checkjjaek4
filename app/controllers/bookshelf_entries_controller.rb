class BookshelfEntriesController < ApplicationController
  include BookShowContext

  before_action :set_bookshelf_entry, only: :edit

  def edit
    authorize @bookshelf_entry
    @book = @bookshelf_entry.book
    @sticker_definitions = StickerDefinition.alphabetical
  end

  def create
    attempts ||= 0
    @book = book_for_create
    return redirect_to_invalid_search_result if @book.blank?
    if @book.new_record? && @book.canonical_isbn.blank? && @book.external_url.blank?
      return redirect_to_search_error("book_search.errors.missing_identity")
    end

    with_active_user_lock do
      @book.save! if @book.new_record?
      user_book = current_user.user_books.find_or_create_by!(book: @book)
      first_registration = user_book.previously_new_record?

      @bookshelf_entry = current_user.bookshelf_entries.find_or_initialize_by(book: @book)
      authorize @bookshelf_entry

      new_placement = @bookshelf_entry.new_record?
      @bookshelf_entry.user_book = user_book
      @bookshelf_entry.bookshelf = bookshelf_for_create if new_placement && bookshelf_entry_params[:bookshelf_id].present?
      @bookshelf_entry.save! if new_placement
      # Keep the stored selections when giving a previously removed book a new placement.
      save_reading_record! if first_registration || !new_placement

      if new_placement
        BookActivities::RecordBookshelfEntryChange.call(
          bookshelf_entry: @bookshelf_entry,
          was_new_record: true
        )
      end
    end

    if book_search_result_source?
      prepare_book_search_result_card
      flash.now[:notice] = t("bookshelf_entries.notices.created")

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to book_path(@book, group_id: group_context_id, return_to: view_context.validated_jjaek_return_path(params[:return_to])), notice: t("bookshelf_entries.notices.created") }
      end
    else
      redirect_to book_path(@book, group_id: group_context_id, return_to: view_context.validated_jjaek_return_path(params[:return_to]), tab: reading_tab),
                  notice: t("bookshelf_entries.notices.created")
    end
  rescue ActiveRecord::RecordInvalid => error
    return render_shelf_error(error.record.errors.full_messages.to_sentence) if inline_shelf_error?
    redirect_back fallback_location: book_search_path(group_id: group_context_id),
                  alert: error.record.errors.full_messages.to_sentence.presence || t("book_search.errors.invalid_result")
  rescue ActiveRecord::RecordNotFound
    raise unless inline_shelf_error?
    render_shelf_error(t("book_search.errors.invalid_result"), status: :not_found)
  rescue Pundit::NotAuthorizedError
    raise unless inline_shelf_error?
    render_shelf_error(t("book_search.errors.invalid_result"), status: :forbidden)
  rescue Book::IdentityConflict
    redirect_to_search_error("book_search.errors.identity_conflict")
  rescue ActiveRecord::RecordNotUnique => error
    if attempts.zero? && book_identity_index_conflict?(error) && reusable_book_after_conflict?
      attempts += 1
      retry
    end

    redirect_to_search_error("book_search.errors.identity_conflict")
  end

  def update
    saved_reading_state = with_active_user_lock do
      set_bookshelf_entry
      authorize @bookshelf_entry

      user_book = @bookshelf_entry.user_book
      previous_status = user_book.status
      previous_sticker_definition_ids = user_book.sticker_definition_ids
      save_reading_record!
      BookActivities::RecordBookshelfEntryChange.call(
        bookshelf_entry: @bookshelf_entry,
        was_new_record: false,
        previous_status: previous_status,
        previous_sticker_definition_ids: previous_sticker_definition_ids
      )
      reading_state
    end

    respond_to do |format|
      format.json { render json: saved_reading_state }
      format.html do
        redirect_to book_path(@bookshelf_entry.book, group_id: group_context_id,
          return_to: view_context.validated_jjaek_return_path(params[:return_to]), tab: reading_tab),
          notice: t("bookshelf_entries.notices.updated"), status: :see_other
      end
    end
  rescue ActiveRecord::RecordInvalid => error
    message = error.record.errors.full_messages.to_sentence
    @bookshelf_entry.reload
    respond_to do |format|
      format.json do
        render json: reading_state.merge(error: message), status: :unprocessable_content
      end
      format.html do
        @reading_state_form_values = bookshelf_entry_params.slice(:status, :sticker_definition_ids).to_h
        @bookshelf_entry.errors.add(:base, message)
        prepare_book_show_failure
        render "books/show", status: :unprocessable_content
      end
    end
  end

  def move
    target_bookshelf = with_active_user_lock do
      set_bookshelf_entry
      authorize @bookshelf_entry, :move?

      target = current_user.bookshelves.find(params[:bookshelf_id])
      @bookshelf_entry.move_to_bookshelf!(target, before_entry: before_entry_for_move)
      target
    end

    location = bookshelf_entry_move_redirect_path(target_bookshelf)
    notice = t("bookshelf_entries.notices.moved", bookshelf_name: target_bookshelf.name)
    respond_to do |format|
      format.json do
        flash[:notice] = notice
        render json: { location: }
      end
      format.any(:html, :turbo_stream) { redirect_to location, notice: }
    end
  rescue ActiveRecord::RecordInvalid
    message = @bookshelf_entry.errors.full_messages.to_sentence
    respond_to do |format|
      format.json { render json: { error: message }, status: :unprocessable_content }
      format.any(:html, :turbo_stream) { redirect_to bookshelf_entry_move_redirect_path(@bookshelf_entry.bookshelf), alert: message }
    end
  end

  def bulk_move
    target_bookshelf, moved_count = with_active_user_lock do
      authorize BookshelfEntry, :bulk_move?

      target = current_user.bookshelves.find(params[:target_bookshelf_id])
      count = BookshelfEntry.bulk_move_to_bookshelf!(entries: bulk_move_entries, target_bookshelf: target)
      [ target, count ]
    end

    redirect_to transfer_user_library_path(current_user, bulk_move_redirect_options(target_bookshelf)),
                notice: t("bookshelf_entries.notices.bulk_moved", count: moved_count, bookshelf_name: target_bookshelf.name)
  rescue ActiveRecord::RecordInvalid
    redirect_to transfer_user_library_path(current_user, bookshelf_organize_options || {}),
                alert: t("bookshelf_entries.alerts.bulk_move_failed")
  end

  def reorder
    bookshelf = with_active_user_lock do
      bookshelf = current_user.bookshelves.find(params[:bookshelf_id])
      authorize BookshelfEntry, :reorder?

      BookshelfEntry.reorder_within!(bookshelf:, ordered_ids: params[:bookshelf_entry_ids])
      bookshelf
    end
    options = { bookshelf_id: bookshelf.id, sort: "manual" }

    respond_to do |format|
      format.json { head :no_content }
      format.any(:html, :turbo_stream) { redirect_to user_library_path(current_user, options), status: :see_other }
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { error: t("bookshelf_entries.alerts.reorder_failed") }, status: :unprocessable_content }
      format.any(:html, :turbo_stream) { head :unprocessable_content }
    end
  end

  def destroy
    with_active_user_lock do
      set_bookshelf_entry
      authorize @bookshelf_entry
      if params[:bookshelf_id].present? && @bookshelf_entry.bookshelf_id.to_s != params[:bookshelf_id].to_s
        raise ActiveRecord::RecordNotFound
      end
      @bookshelf_entry.destroy!
    end

    redirect_to bookshelf_entry_destroy_redirect_path, notice: t("bookshelf_entries.notices.destroyed"), status: :see_other
  rescue ActiveRecord::RecordNotDestroyed
    raise unless params[:bookshelf_id].present?

    redirect_to bookshelf_entry_destroy_redirect_path, alert: t("bookshelf_entries.alerts.destroy_failed"), status: :see_other
  end

  def bulk_destroy
    authorize BookshelfEntry, :bulk_destroy?

    source_id = params[:source_bookshelf_id].to_s
    return head :not_found unless source_id.match?(/\A[1-9]\d*\z/)

    ids = bulk_destroy_entry_ids
    return head :not_found unless ids

    return_path = nil
    with_active_user_lock do
      source_bookshelf = current_user.bookshelves.find_by(id: source_id)
      next unless source_bookshelf

      entries = policy_scope(BookshelfEntry).where(bookshelf: source_bookshelf, id: ids).to_a
      next unless entries.size == ids.size
      options = bookshelf_organize_options || { source_bookshelf_id: source_bookshelf.id, target_bookshelf_id: params[:target_bookshelf_id].presence }
      return_path = transfer_user_library_path(current_user, options)
      entries.each(&:destroy!)
    end

    return head :not_found unless return_path

    redirect_to return_path, notice: t("bookshelf_entries.notices.bulk_destroyed", count: ids.size), status: :see_other
  rescue ActiveRecord::RecordNotDestroyed
    redirect_to return_path, alert: t("bookshelf_entries.alerts.bulk_destroy_failed"), status: :see_other
  end

  private

  def set_bookshelf_entry
    @bookshelf_entry = current_user.bookshelf_entries.find(params[:id])
  end

  def bookshelf_entry_params
    params.fetch(:bookshelf_entry, {}).permit(:bookshelf_id, :status, sticker_definition_ids: [])
  end

  def bulk_move_entries
    requested_ids = Array(params[:bookshelf_entry_ids]).reject(&:blank?).map(&:to_i).uniq
    entries_by_id = current_user.bookshelf_entries.where(id: requested_ids).index_by(&:id)
    raise ActiveRecord::RecordNotFound if entries_by_id.size != requested_ids.size

    requested_ids.map { |id| entries_by_id.fetch(id) }
  end

  def bulk_destroy_entry_ids
    ids = params[:bookshelf_entry_ids]
    unless ids.is_a?(Array) && ids.present? && ids.all? { |id| id.to_s.match?(/\A[1-9][0-9]*\z/) }
      return nil
    end

    ids.map(&:to_i).uniq
  end

  def bulk_move_redirect_options(target_bookshelf)
    bookshelf_organize_options || {
      source_bookshelf_id: bulk_move_source_bookshelf_id(target_bookshelf),
      target_bookshelf_id: bulk_move_target_bookshelf_id(target_bookshelf)
    }.compact
  end

  def bookshelf_organize_options
    return unless params[:return_to] == "library_organize"

    { mode: "organize", source_bookshelf_id: params[:source_bookshelf_id].presence }
  end

  def bulk_move_source_bookshelf_id(target_bookshelf)
    return target_bookshelf.id if params[:return_to_target_as_source].present?

    params[:source_bookshelf_id].presence
  end

  def bulk_move_target_bookshelf_id(target_bookshelf)
    return if params[:return_to_target_as_source].present?

    target_bookshelf.id
  end

  def book_for_create
    return Book.find(params[:book_id]) if params[:book_id].present?

    @search_result_attributes = BookSearches::ResultToken.verify(params[:search_result_token], user: current_user)
    return if @search_result_attributes.blank?

    Book.find_or_initialize_from_search(@search_result_attributes)
  end

  def book_identity_index_conflict?(error)
    error.message.match?(/index_books_on_(canonical_isbn|external_url)_unique/)
  end

  def reusable_book_after_conflict?
    return false if @search_result_attributes.blank?

    Book.find_or_initialize_from_search(@search_result_attributes).persisted?
  rescue Book::IdentityConflict
    false
  end

  def redirect_to_search_error(key)
    return render_shelf_error(t(key)) if inline_shelf_error?
    redirect_to book_search_path(group_id: group_context_id), alert: t(key), status: :see_other
  end

  def redirect_to_invalid_search_result
    return render_shelf_error(t("book_search.errors.invalid_result")) if inline_shelf_error?
    redirect_to book_search_path(group_id: group_context_id),
                alert: t("book_search.errors.invalid_result"), status: :see_other
  end

  def bookshelf_for_create
    current_user.bookshelves.find(bookshelf_entry_params[:bookshelf_id])
  end

  def before_entry_for_move
    id = params[:before_entry_id]
    return if id.nil? || id == ""
    raise ActiveRecord::RecordNotFound unless id.to_s.match?(/\A[0-9]+\z/)

    current_user.bookshelf_entries.find(id)
  end

  def inline_shelf_error?
    request.format.turbo_stream? &&
      (verified_shelf_error_target.present? || params[:bookshelf_entry_source].in?(%w[jjaek_attachment jjaek_attachment_search]))
  end

  def verified_shelf_error_target
    return unless book_search_result_source? && params[:shelf_error_target].is_a?(String)

    Rails.application.message_verifier("shelf_error_target").verified(
      params[:shelf_error_target], purpose: "user:#{current_user.id}:#{params[:bookshelf_entry_source]}"
    )
  end

  def render_shelf_error(message, status: :unprocessable_content)
    if (target = verified_shelf_error_target)
      stream = turbo_stream.update(target, partial: "book_searches/shelf_selection_error", locals: { message: message })
    else
      flash.now[:alert] = message
      stream = turbo_stream.update("flash-messages", partial: "shared/flash")
    end
    render turbo_stream: stream, status:
  end

  def book_search_result_source?
    params[:bookshelf_entry_source].in?(%w[book_search jjaek_attachment jjaek_attachment_search])
  end

  def prepare_book_search_result_card
    attributes = @search_result_attributes || @book.attributes.symbolize_keys
    @book_search_result = {
      existing_book_id: (@book.id if params[:book_id].present?),
      title: attributes[:title],
      authors_text: attributes[:authors_text],
      publisher: attributes[:publisher],
      thumbnail: attributes[:thumbnail],
      isbn: attributes[:isbn],
      contents_excerpt: attributes[:description],
      url: attributes[:external_url],
      shelved_book_id: @book.id,
      bookshelf_entry: @bookshelf_entry
    }
    @bookshelves = current_user.bookshelves.default_first
  end

  def prepare_book_show_failure
    @book = @bookshelf_entry.book
    @sticker_definitions = StickerDefinition.alphabetical
    @group = policy_scope(Group).find(group_context_id) if group_context_id
    authorize @group, :create_jjaek? if @group
    @jjaek = Jjaek.new(user: current_user, group: @group)
    authorize @jjaek
    @selected_books = [ @book ]
    @selected_book_keys = [ @book.id.to_s ]
    prepare_book_show_read_context
  end

  def save_reading_record!
    attributes = bookshelf_entry_params.slice(:status, :sticker_definition_ids)
    return if attributes.empty?

    user_book = @bookshelf_entry.user_book
    user_book.update!(attributes)
    @bookshelf_entry.touch if user_book.saved_change_to_status?
  end

  def group_context_id
    params[:group_id].presence
  end

  def reading_state
    user_book = @bookshelf_entry.user_book
    { status: user_book.status, sticker_definition_ids: user_book.sticker_definition_ids }
  end

  def bookshelf_entry_move_redirect_path(bookshelf)
    if params[:return_to] == "book"
      return book_path(@bookshelf_entry.book, group_id: group_context_id, tab: reading_tab,
        return_to: view_context.validated_jjaek_return_path(params[:book_return_to]))
    end
    return bookshelf_entry_transfer_redirect_path(bookshelf) if params[:return_to] == "library_transfer"

    options = { bookshelf_id: bookshelf&.id }
    options[:sort] = library_sort_param if library_sort_param

    user_library_path(current_user, options.compact)
  end

  def reading_tab
    "reading" if params[:tab] == "reading"
  end

  def bookshelf_entry_destroy_redirect_path
    case params[:return_to]
    when "book"
      book_path(@bookshelf_entry.book, group_id: group_context_id,
        return_to: view_context.validated_jjaek_return_path(params[:book_return_to]))
    when "library_transfer"
      bookshelf_entry_transfer_redirect_path(@bookshelf_entry.bookshelf)
    when "library"
      user_library_path(current_user, {
        bookshelf_id: params[:bookshelf_id].presence, sort: library_sort_param,
        library_tab: ("bookshelves" if params[:library_tab] == "bookshelves"),
        notes_page: Integer(params[:notes_page], exception: false)
      }.compact)
    else
      user_library_path(current_user)
    end
  end

  def bookshelf_entry_transfer_redirect_path(bookshelf)
    options = {
      source_bookshelf_id: params[:source_bookshelf_id].presence || @bookshelf_entry.bookshelf_id,
      target_bookshelf_id: params[:target_bookshelf_id].presence || bookshelf&.id
    }

    transfer_user_library_path(current_user, options.compact)
  end

  def library_sort_param
    return "manual" if params[:before_entry_id].present?

    params[:sort] if BookshelfEntry::PROFILE_SORTS.include?(params[:sort])
  end
end
