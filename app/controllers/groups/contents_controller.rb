module Groups
  class ContentsController < ApplicationController
    before_action :set_group

    def index
      authorize @group, :view_content_inventory?
    end

    private

    def set_group
      @group = Group.find(params[:id])
    end
  end
end
