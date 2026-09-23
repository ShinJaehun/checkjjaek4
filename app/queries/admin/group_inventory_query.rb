module Admin
  class GroupInventoryQuery
    SORTS = { "recent" => { created_at: :desc }, "oldest" => { created_at: :asc }, "name" => { name: :asc, id: :asc } }.freeze
    LEGACY_OPERATION_STATUSES = %w[normal suspended].freeze

    def initialize(scope, params) = (@scope, @params = scope, params)

    def call
      result = @scope.joins(:group_admin).select("groups.*, (SELECT COUNT(*) FROM group_memberships WHERE group_memberships.group_id = groups.id AND group_memberships.status = #{GroupMembership.statuses[:active]}) AS active_members_count")
      term = @params[:q].to_s.strip
      result = result.where("groups.name ILIKE :term OR users.name ILIKE :term OR users.email ILIKE :term", term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%") if term.present?
      result = result.where(group_type: @params[:group_type]) if Group.group_types.key?(@params[:group_type])
      result = apply_status_filter(result)
      result.order(SORTS.fetch(@params[:sort].to_s, SORTS["recent"]))
    end

    private

    def apply_status_filter(result)
      if LEGACY_OPERATION_STATUSES.include?(@params[:operation_status])
        return apply_legacy_status_filters(result)
      end

      case @params[:status]
      when "pending_approval"
        result.where(lifecycle_status: :pending_approval, closed_at: nil, operation_suspended_at: nil)
      when "active"
        result.where(lifecycle_status: :active, operation_suspended_at: nil)
      when "inactive"
        result.where(lifecycle_status: :inactive, operation_suspended_at: nil)
      when "reactivation_pending"
        result.where(lifecycle_status: :pending_approval, operation_suspended_at: nil).where.not(closed_at: nil)
      when "suspended"
        result.where.not(operation_suspended_at: nil)
      else
        result
      end
    end

    def apply_legacy_status_filters(result)
      result = result.where(lifecycle_status: @params[:status]) if Group.lifecycle_statuses.key?(@params[:status])
      return result.where(lifecycle_status: :active, operation_suspended_at: nil) if @params[:operation_status] == "normal"

      result.where(lifecycle_status: :active).where.not(operation_suspended_at: nil)
    end
  end
end
