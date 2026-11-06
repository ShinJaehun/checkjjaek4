class JjaekBooksController < ApplicationController
  include RecommendationSelection

  def index
    prepare_book_selection_context
    prepare_recommendation_selection(preserve_on_error: true)
    @query = params[:query].to_s
    @page = 1
    render layout: false
  end
end
