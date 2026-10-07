module Groups
  class ContentsController < ApplicationController
    before_action :set_group

    def index
      authorize @group, :view_content_inventory?

      @content_section = permitted_content_section
      @thread_page = ContentThreadQuery.new(
        group: @group,
        jjaek_scope: @group.jjaeks,
        comment_scope: Comment.where(jjaek_id: @group.jjaeks.select(:id)),
        content_section: @content_section,
        params:
      ).call
      @content_threads = @thread_page.records
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
