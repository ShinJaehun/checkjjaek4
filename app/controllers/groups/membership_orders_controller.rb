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

    def hide
      group = managed_group
      group.with_lock do
        authorize group, :hide_from_list?
        current_user.with_lock("FOR NO KEY UPDATE") do
          current_user.group_list_hidings.find_or_create_by!(group:)
        end
      end
      redirect_to edit_groups_membership_order_path, notice: t("groups.membership_order.hidden"), status: :see_other
    end

    def restore
      group = managed_group
      group.with_lock do
        current_user.with_lock("FOR NO KEY UPDATE") do
          current_user.group_list_hidings.where(group:).delete_all
        end
      end
      redirect_to edit_groups_membership_order_path, notice: t("groups.membership_order.restored"), status: :see_other
    end

    private

    def authorize_ordering
      authorize Group, :index?
      @current_groups = policy_scope(Group, policy_scope_class: GroupPolicy::MembershipScope)
      @past_groups = policy_scope(Group, policy_scope_class: GroupPolicy::PastMembershipScope)
      @groups = @current_groups.where.not(id: current_user.group_list_hidings.select(:group_id))
    end

    def prepare_memberships
      @memberships = GroupMembership.displayed_for(user: current_user, groups: @groups).preload(:group).to_a
      hidden_ids = current_user.group_list_hidings.pluck(:group_id)
      past_groups = @past_groups
        .select(:id, :name, :group_type, :lifecycle_status, :operation_suspended_at, :closed_at).index_by(&:id)
      @past_group_states = GroupMembershipEvent.past_states_for(user: current_user, groups: past_groups.values)
      @past_groups = @past_group_states.keys.map { |id| past_groups.fetch(id) }
      @hidden_groups = @current_groups.where(id: hidden_ids).to_a + @past_groups.select { |group| group.id.in?(hidden_ids) }
      @past_groups = @past_groups.reject { |group| group.id.in?(hidden_ids) }
      @removable_group_ids = @memberships.select(&:removable_from_list?).map(&:group_id)
    end

    def managed_group
      @current_groups.or(@past_groups).find(params[:group_id])
    end
  end
end
