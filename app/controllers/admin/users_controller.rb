module Admin
  class UsersController < ApplicationController
    def index
      authorize User, :view_admin_inventory?
      users = policy_scope(User, policy_scope_class: UserPolicy::AdminInventoryScope)
      scope = UserInventoryQuery.new(users, params).call.includes(avatar_attachment: :blob)
      @inventory_page = InventoryPage.new(scope, page: params[:page], per_page: params[:per_page])
      @users = @inventory_page.records
      @latest_activities_by_user_id = LatestContentActivityQuery.new(
        owner_type: :user,
        owner_ids: @users.map(&:id)
      ).call
    end

    def show
      @user = User.find_by_public_param!(params[:id])
      authorize @user, :view_admin_inventory?
      prepare_user_identity
      @return_params = params.permit(:content, :q, :location, :status, :sort, :all_page, :per_page,
                                     inventory: %i[q status role sort page per_page])
      @can_suspend = policy(@user).suspend?
      @can_restore = policy(@user).restore?
      @account_history_entries = UserAccountHistoryQuery.new(@user).call
      @administered_groups = @user.administered_groups.order(created_at: :desc).load
      @joined_groups = @user.joined_groups.order(created_at: :desc).load
      @activity_counts = user_content_query(params: @return_params).activity_counts
    end

    def content
      @user = User.find_by_public_param!(params[:id])
      authorize @user, :view_admin_inventory?
      prepare_user_identity
      @content_section = permitted_content_section
      @content_location = permitted_content_location
      @content_filter_params = params.permit(:q, :location, :status, :sort, :per_page,
                                             inventory: %i[q status role sort page per_page])
      @return_params = @content_filter_params.merge(params.permit(:content, :all_page))

      @timeline_page = user_content_query(params:, content_section: @content_section).call
      @timeline_items = @timeline_page.records
      @activity_counts = @timeline_page.activity_counts
    end

    private

    def user_content_query(params:, content_section: "all")
      UserContentTimelineQuery.new(
        jjaek_scope: policy_scope(Jjaek, policy_scope_class: JjaekPolicy::AdminInventoryScope).where(user: @user),
        comment_scope: policy_scope(Comment, policy_scope_class: CommentPolicy::AdminInventoryScope).where(user: @user),
        content_section:,
        params:
      )
    end

    def prepare_user_identity
      @account_status = @user.moderation_status
      @has_administered_groups = @user.administered_groups.exists?
    end

    def permitted_content_section
      section = params[:content].to_s
      %w[general group requote comments].include?(section) ? section : "all"
    end

    def permitted_content_location
      location = params[:location].to_s
      location if %w[personal group].include?(location)
    end
  end
end
