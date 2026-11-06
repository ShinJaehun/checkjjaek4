class BookSearchesController < ApplicationController
  include BookSearchResults
  include RecommendationSelection

  def show
    authorize :book_search, :show?
    if params[:attachment] == "1"
      prepare_book_selection_context
      @recommendation_context = true
      prepare_recommendation_selection(preserve_on_error: true)
      prepare_book_search_results
      return
    end
    if params[:editing_jjaek_id].present?
      jjaek = Jjaek.find(params[:editing_jjaek_id])
      authorize jjaek, :update?
      return redirect_to edit_jjaek_path(jjaek, return_to: view_context.validated_jjaek_return_path(params[:return_to]))
    end
    if recommendation_context?
      group = find_group_context
      authorize group, :create_jjaek? if group
      options = { return_to: view_context.validated_jjaek_return_path(params[:search_origin]) }
      return redirect_to(group ? new_group_jjaek_path(group, options) : new_jjaek_path(options))
    end
    @group = find_group_context
    authorize @group, :create_jjaek? if @group.present?
    prepare_book_search_results
  end

  private

  def find_group_context
    return if params[:group_id].blank?

    policy_scope(Group).find(params[:group_id])
  end
end
