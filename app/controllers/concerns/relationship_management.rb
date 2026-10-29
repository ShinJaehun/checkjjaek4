module RelationshipManagement
  private

  def relationship_page
    @relationship_page ||= RelationshipsQuery.new(user: current_user, tab: params[:tab], query: params[:q], page: params[:page])
  end

  def relationships_return_path
    account_relationships_path(relationship_page.navigation_params)
  end

  def render_relationships_change(notice:)
    relationship_page
    flash.now[:notice] = notice

    respond_to do |format|
      format.turbo_stream do
        if params[:page].present? && params[:page].to_s != relationship_page.page.to_s
          redirect_to relationships_return_path, notice: notice, status: :see_other
        else
          render "relationships/change"
        end
      end
      format.html { redirect_to relationships_return_path, notice: notice, status: :see_other }
    end
  end
end
