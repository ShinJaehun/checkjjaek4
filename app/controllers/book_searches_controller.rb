class BookSearchesController < ApplicationController
  def show
    authorize :book_search, :show?

    @query = params[:query].to_s.strip
    @page = normalized_page
    @results = []
    @meta = {}
    @has_previous_page = false
    @has_next_page = false
    return if @query.blank?

    result = BookSearches::SearchService.call(query: @query, page: @page)
    @results = result[:results]
    @meta = result[:meta]
    @has_previous_page = @page > 1
    @has_next_page = @meta[:is_end] == false
  rescue BookSearches::KakaoAdapter::Error
    flash.now[:alert] = t("book_search.errors.generic")
  end

  private

  def normalized_page
    page = Integer(params[:page], exception: false)
    page&.positive? ? page : 1
  end
end
