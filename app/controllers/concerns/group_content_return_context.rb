module GroupContentReturnContext
  FILTER_KEYS = %i[content content_q content_status content_sort all_page].freeze

  def self.filter_params(params)
    params.permit(*FILTER_KEYS).to_h.compact_blank
  end

  private

  def prepare_group_content_return(default_path:)
    @group_content_return = params[:return_to] == "group_content" && @jjaek.group.present?
    @return_context_params = {}
    @return_path = default_path
    return unless @group_content_return

    filters = GroupContentReturnContext.filter_params(params)
    @return_context_params = filters.merge(return_to: "group_content")
    @return_path = content_group_path(@jjaek.group, filters)
  end
end
