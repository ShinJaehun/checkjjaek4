class BooksController < ApplicationController
  before_action :set_book, only: :show

  def lookup
    @group = find_group_context
    authorize @group, :create_jjaek? if @group.present?
    attributes = BookSearches::ResultToken.verify(params[:search_result_token], user: current_user)
    return redirect_to_invalid_search_result if attributes.blank?

    @book = Book.find_or_initialize_from_search(attributes)
    authorize @book, :show?
    return redirect_to_invalid_search_result if @book.invalid?
    return redirect_to book_path(@book, group_id: @group&.id, return_to: view_context.validated_jjaek_return_path(params[:return_to])) if @book.persisted?

    @search_result_token = params[:search_result_token]
    @bookshelves = current_user.bookshelves.default_first
    @jjaeks = Jjaek.none
    render :show
  rescue Book::IdentityConflict
    redirect_to book_search_path(group_id: @group&.id), alert: t("book_search.errors.identity_conflict")
  end

  def show
    @group = find_group_context
    authorize @group, :create_jjaek? if @group.present?
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book)
    prepare_book_write_context if @bookshelf_entry.present?
    prepare_book_show_read_context
  end

  private

  def prepare_book_write_context
    authorize @bookshelf_entry
    @quoted_jjaek = find_quoted_jjaek
    @jjaek = Jjaek.new(user: current_user, book: @book, group: @group, quoted_jjaek: @quoted_jjaek)
    authorize @jjaek
    @sticker_definitions = StickerDefinition.alphabetical
  end

  def find_quoted_jjaek
    return unless params[:quote_id].present?

    policy_scope(@book.jjaeks).find(params[:quote_id])
  end

  def set_book
    @book = Book.find(params[:id])
    authorize @book, :show?
  end

  def find_group_context
    return if params[:group_id].blank?

    policy_scope(Group).find(params[:group_id])
  end

  def redirect_to_invalid_search_result
    redirect_to book_search_path(group_id: @group&.id), alert: t("book_search.errors.invalid_result")
  end
end
