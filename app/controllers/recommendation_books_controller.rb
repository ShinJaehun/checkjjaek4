class RecommendationBooksController < ApplicationController
  include RecommendationSelection
  include BookSearchResults
  before_action :prepare_selection

  def create
    book = book_for_selection
    validate_recommendation_book!(book)
    unless recommendation_book_selected?(book)
      if @selected_books.size >= Jjaek::MAX_RECOMMENDATION_BOOKS
        flash.now[:alert] = t("recommendations.limit_reached", count: Jjaek::MAX_RECOMMENDATION_BOOKS)
        return respond_with_selection(status: :unprocessable_content)
      end
      key = book.persisted? ? book.id.to_s : cache_external_recommendation(params[:search_result_token])
      @selected_book_keys << key
      @selected_books << book
    end

    respond_with_selection
  rescue Book::IdentityConflict
    flash.now[:alert] = t("recommendations.invalid_selection")
    respond_with_selection
  end

  def destroy
    if (index = @selected_book_keys.index(params[:id]))
      @selected_book_keys.delete_at(index)
      @selected_books.delete_at(index)
    end
    respond_with_selection(status: enforce_recommendation_limit ? :ok : :unprocessable_content)
  end

  private

  def prepare_selection
    @group = policy_scope(Group).find(params[:group_id]) if params[:group_id].present?
    @jjaek = Jjaek.new(user: current_user, group: @group, recommendation: true)
    authorize @jjaek, :create?
    unless prepare_recommendation_selection(redirect_on_error: false, enforce_limit: action_name != "destroy")
      respond_with_selection(status: :unprocessable_content)
    end
  end

  def respond_with_selection(status: :ok)
    respond_to do |format|
      format.turbo_stream do
        @recommendation_context = true
        prepare_book_search_results
        render :update, status:
      end
      format.html do
        flash.keep(:alert)
        redirect_to selection_path, status: :see_other
      end
    end
  end

  def book_for_selection
    if params[:book_id].present?
      id = params[:book_id]
      raise Book::IdentityConflict unless id.is_a?(String) && id.match?(/\A[1-9]\d*\z/)

      return Book.find_by(id:)
    end
    return unless params[:search_result_token].is_a?(String)

    attributes = BookSearches::ResultToken.verify(params[:search_result_token], user: current_user)
    Book.find_or_initialize_from_search(attributes) if attributes.present?
  end

  def selection_path
    options = {
      recommendation: 1,
      selected_books: @selected_book_keys,
      query: params[:query],
      page: params[:page],
      search_origin: view_context.recommendation_origin_path
    }

    book_search_path(options.merge(group_id: @group&.id))
  end
end
