module Groups
  class ContentsController < ApplicationController
    before_action :set_group

    def index
      authorize @group, :view_content_inventory?

      @content_section = permitted_content_section
      @content_filter_params = params.permit(:content_q, :content_status, :content_sort)
      @content_status = params[:content_status] if %w[active hidden deleted].include?(params[:content_status])
      @content_sort = %w[recent oldest].include?(params[:content_sort]) ? params[:content_sort] : "recent"
      @thread_page = ContentThreadQuery.new(
        group: @group,
        jjaek_scope: @group.jjaeks,
        comment_scope: Comment.where(jjaek_id: @group.jjaeks.select(:id)),
        content_section: @content_section,
        params:
      ).call
      @content_threads = @thread_page.records
      @direct_linkable_roots = @content_threads.to_h do |thread|
        [ thread.root.id, policy(thread.root).show? ]
      end
    end

    private

    def set_group
      @group = Group.find(params[:id])
    end

    def permitted_content_section
      section = params[:content].to_s
      %w[general book comments].include?(section) ? section : "all"
    end
  end
end
