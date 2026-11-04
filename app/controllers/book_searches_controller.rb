class BookSearchesController < ApplicationController
  include BookSearchResults
  include RecommendationSelection

  def show
    authorize :book_search, :show?
    @group = find_group_context
    authorize @group, :create_jjaek? if @group.present?
    @recommendation_context = recommendation_context?
    @recommendation_selection_reset = flash.delete(:recommendation_selection_reset)
    return if @recommendation_context && !prepare_recommendation_selection

    prepare_book_search_results
    if @recommendation_context
      @jjaek = Jjaek.new(user: current_user, group: @group, recommendation: true)
      authorize @jjaek, :create?
    end
  end

  private

  def find_group_context
    return if params[:group_id].blank?

    policy_scope(Group).find(params[:group_id])
  end
end
