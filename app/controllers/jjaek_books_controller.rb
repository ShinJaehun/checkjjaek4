# Temporary book selection; persistence belongs to JjaeksController.
class JjaekBooksController < ApplicationController
  include BookSelection
  include BookSearchResults
  before_action :prepare_selection, only: %i[create destroy]

  def index
    prepare_book_selection_context
    prepare_book_selection(preserve_on_error: true)
    @query = params[:query].to_s
    @page = 1
    render layout: false
  end

  def create
    book = if params[:book_id].present?
      raise Book::IdentityConflict unless params[:book_id].is_a?(String) && params[:book_id].match?(/\A[1-9]\d*\z/)
      Book.find_by(id: params[:book_id])
    else
      raise Book::IdentityConflict unless params[:search_result_token].is_a?(String)
      attributes = BookSearches::ResultToken.verify(params[:search_result_token], user: current_user)
      Book.find_or_initialize_from_search(attributes) if attributes.present?
    end
    validate_selected_book!(book)
    unless selected_book?(book)
      if @selected_books.size >= Jjaek::MAX_ATTACHED_BOOKS
        flash.now[:alert] = t("jjaek_books.limit", count: Jjaek::MAX_ATTACHED_BOOKS)
        return respond_with_selection(status: :unprocessable_content)
      end
      @selected_book_keys << (book.persisted? ? book.id.to_s : cache_external_book(params[:search_result_token]))
      @selected_books << book
    end
    respond_with_selection
  rescue Book::IdentityConflict
    flash.now[:alert] = t("jjaek_books.invalid_selection")
    respond_with_selection(status: :unprocessable_content)
  end

  def destroy
    if (index = @selected_book_keys.index(params[:id]))
      @selected_book_keys.delete_at(index)
      @selected_books.delete_at(index)
    end
    respond_with_selection
  end

  private

  def prepare_selection
    prepare_book_selection_context
    unless prepare_book_selection(preserve_on_error: true)
      return respond_with_selection(status: :unprocessable_content)
    end
    if @selected_books.size > Jjaek::MAX_ATTACHED_BOOKS
      flash.now[:alert] = t("jjaek_books.limit", count: Jjaek::MAX_ATTACHED_BOOKS)
      respond_with_selection(status: :unprocessable_content)
    end
  end

  def respond_with_selection(status: :ok)
    @book_selection_context = true
    prepare_book_search_results
    respond_to do |format|
      format.turbo_stream { render :update, status: }
      format.html { redirect_to book_search_path(view_context.book_selection_search_params), status: :see_other }
    end
  end
end
