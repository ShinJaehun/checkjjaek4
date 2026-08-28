module Admin
  class GroupInventoryQuery
    SORTS = { "recent" => { created_at: :desc }, "oldest" => { created_at: :asc }, "name" => { name: :asc, id: :asc } }.freeze

    def initialize(scope, params) = (@scope, @params = scope, params)

    def call
      result = @scope.joins(:group_admin).select("groups.*, (SELECT COUNT(*) FROM group_memberships WHERE group_memberships.group_id = groups.id AND group_memberships.status = #{GroupMembership.statuses[:active]}) AS active_members_count")
      term = @params[:q].to_s.strip
      result = result.where("groups.name ILIKE :term OR users.name ILIKE :term OR users.email ILIKE :term", term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%") if term.present?
      result = result.where(group_type: @params[:group_type]) if Group.group_types.key?(@params[:group_type])
      result = result.where(lifecycle_status: @params[:status]) if Group.lifecycle_statuses.key?(@params[:status])
      result.order(SORTS.fetch(@params[:sort].to_s, SORTS["recent"]))
    end
  end
end
