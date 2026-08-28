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
      @administered_groups = @user.administered_groups.order(created_at: :desc).load
      @membership_counts = @user.group_memberships.group(:status).count
    end
  end
end
