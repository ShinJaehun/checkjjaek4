module Groups
  class MembershipOrdersController < ApplicationController
    before_action :authorize_ordering

    def edit
      prepare_memberships
    end

    def update
      GroupMembership.reorder_for!(user: current_user, groups: @groups, ordered_ids: params[:membership_ids])
      redirect_to groups_path, notice: t("groups.membership_order.saved"), status: :see_other
    rescue GroupMembership::InvalidOrder, ActiveRecord::RecordInvalid
      prepare_memberships
      flash.now[:alert] = t("groups.membership_order.failed")
      render :edit, status: :unprocessable_content
    end

    private

    def authorize_ordering
      authorize Group, :index?
      @groups = policy_scope(Group, policy_scope_class: GroupPolicy::MembershipScope)
    end

    def prepare_memberships
      @memberships = GroupMembership.displayed_for(user: current_user, groups: @groups).preload(:group).to_a
    end
  end
end
