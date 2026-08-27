module Admin
  class UserInventoryQuery
    SORTS = { "recent" => { created_at: :desc }, "oldest" => { created_at: :asc }, "name" => { name: :asc, id: :asc } }.freeze

    def initialize(scope, params)
      @scope, @params = scope, params
    end

    def call
      result = @scope.select("users.*, (SELECT COUNT(*) FROM groups WHERE groups.group_admin_id = users.id) AS administered_groups_count")
      term = @params[:q].to_s.strip
      result = result.where("users.name ILIKE :term OR users.email ILIKE :term", term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%") if term.present?
      result = result.where(withdrawn_at: nil) if @params[:status] == "active"
      result = result.where.not(withdrawn_at: nil) if @params[:status] == "withdrawn"
      result = result.where(global_admin: true) if @params[:global_admin] == "yes"
      result = result.where(global_admin: false) if @params[:global_admin] == "no"
      result = result.where(created_at: parsed_date(@params[:from])..) if parsed_date(@params[:from])
      result = result.where(created_at: ..parsed_date(@params[:to]).end_of_day) if parsed_date(@params[:to])
      result.order(SORTS.fetch(@params[:sort].to_s, SORTS["recent"]))
    end

    private

    def parsed_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
