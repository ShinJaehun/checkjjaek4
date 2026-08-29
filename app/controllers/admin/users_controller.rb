module Admin
  class UsersController < ApplicationController
    def index
      authorize User, :view_admin_inventory?
      users = policy_scope(User, policy_scope_class: UserPolicy::AdminInventoryScope)
      scope = UserInventoryQuery.new(users, params).call
      @inventory_page = InventoryPage.new(scope, page: params[:page])
      @users = @inventory_page.records
    end

    def show
      @user = User.find(params[:id])
      authorize @user, :view_admin_inventory?
      @account_status = @user.moderation_status
      @current_suspension_action = @user.current_suspension_action
      @can_suspend = policy(@user).suspend?
      @can_restore = policy(@user).restore?
      @account_history_entries = UserAccountHistoryQuery.new(@user).call
      @administered_groups = @user.administered_groups.order(created_at: :desc).load
      @membership_counts = @user.group_memberships.group(:status).count
      @content_section = permitted_content_section
      @content_filter_params = params.permit(:q, :location, :status, :sort)

      authored_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::AdminInventoryScope)
        .where(user: @user)
      authored_comments = policy_scope(Comment, policy_scope_class: CommentPolicy::AdminInventoryScope)
        .where(user: @user)

      @timeline_page = UserContentTimelineQuery.new(
        jjaek_scope: authored_jjaeks,
        comment_scope: authored_comments,
        content_section: @content_section,
        params:
      ).call
      @timeline_items = @timeline_page.records
    end

    def suspend
      user = User.find(params[:id])
      authorize user, :suspend?
      Users::SuspendAccount.new(user, actor: current_user, **moderation_action_params).call!

      redirect_to admin_user_path(user), notice: t("admin.users.notices.suspended")
    rescue Users::SuspendAccount::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      redirect_to admin_user_path(user), alert: t("admin.users.alerts.suspend_failed")
    end

    def restore
      user = User.find(params[:id])
      authorize user, :restore?
      Users::RestoreAccount.new(user, actor: current_user, **moderation_action_params).call!

      redirect_to admin_user_path(user), notice: t("admin.users.notices.restored")
    rescue Users::RestoreAccount::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      redirect_to admin_user_path(user), alert: t("admin.users.alerts.restore_failed")
    end

    private

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end

    def permitted_content_section
      section = params[:content].to_s
      %w[general book requote comments].include?(section) ? section : "all"
    end
  end
end
