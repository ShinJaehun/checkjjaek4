module Admin
  class UserInventoryQuery
    SORTS = { "recent" => { created_at: :desc }, "oldest" => { created_at: :asc }, "name" => { name: :asc, id: :asc } }.freeze
    ROLES = %w[global_admin group_admin regular].freeze

    def initialize(scope, params)
      @scope, @params = scope, params
    end

    def call
      result = @scope.select("users.*, (SELECT COUNT(*) FROM groups WHERE groups.group_admin_id = users.id) AS administered_groups_count")
      term = @params[:q].to_s.strip
      result = result.where("users.name ILIKE :term OR users.email ILIKE :term", term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%") if term.present?
      result = result.where(withdrawn_at: nil, suspended_at: nil) if @params[:status] == "active"
      result = result.where(withdrawn_at: nil).where.not(suspended_at: nil) if @params[:status] == "suspended"
      result = result.where.not(withdrawn_at: nil) if @params[:status] == "withdrawn"
      result = apply_role(result)
      result.order(SORTS.fetch(@params[:sort].to_s, SORTS["recent"]))
    end

    private

    def apply_role(result)
      return result unless ROLES.include?(@params[:role])

      case @params[:role]
      when "global_admin"
        result.where(global_admin: true)
      when "group_admin"
        result.where("EXISTS (SELECT 1 FROM groups WHERE groups.group_admin_id = users.id)")
      when "regular"
        result.where(global_admin: false).where("NOT EXISTS (SELECT 1 FROM groups WHERE groups.group_admin_id = users.id)")
      end
    end
  end
end
