class BookSearchesController < ApplicationController
  def show
    authorize :book_search, :show?

    @query = params[:query].to_s.strip
    @results = []
    @meta = {}
    return if @query.blank?

    result = BookSearches::SearchService.call(query: @query)
    @results = result[:results]
    @meta = result[:meta]
  rescue BookSearches::KakaoAdapter::Error
    flash.now[:alert] = t("book_search.errors.generic")
  end
end
