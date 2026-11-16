class BookSearchesController < ApplicationController
  include BookSearchResults
  include BookSelection

  def show
    authorize :book_search, :show?
    if params[:attachment] == "1"
      prepare_book_selection_context
      @book_selection_context = true
      prepare_book_selection(preserve_on_error: true)
      prepare_book_search_results
      return
    end
    @group = find_group_context
    authorize @group, :create_jjaek? if @group.present?
    prepare_book_search_results
    flash.now[:alert] = t("book_search.errors.generic") if @external_search_failed
  end

  private

  def find_group_context
    return if params[:group_id].blank?

    policy_scope(Group).find(params[:group_id])
  end
end
