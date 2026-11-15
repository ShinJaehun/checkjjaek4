class GroupContentThreadQuery
  PER_PAGE = 50
  STATUSES = %w[active hidden deleted].freeze
  SORT_DIRECTIONS = { "recent" => "DESC", "oldest" => "ASC" }.freeze
  ContentThread = Struct.new(:root, :comments, :latest_activity_at, keyword_init: true)

  attr_reader :records, :page, :per_page, :total_count

  def initialize(jjaek_scope:, comment_scope:, content_section:, params:, per_page: PER_PAGE)
    @jjaek_scope = jjaek_scope
    @comment_scope = comment_scope
    @content_section = content_section
    @params = params
    @per_page = per_page
  end

  def call
    prepare_scopes
    apply_content_section
    apply_search
    apply_status
    @total_count = @thread_scope.distinct.count(:id)
    @page = normalized_page
    @records = hydrate(connection.select_all(page_sql))
    self
  end

  def total_pages = @total_pages

  def previous_page
    page - 1 if page > 1
  end

  def next_page
    page + 1 if page < total_pages
  end

  def first_item = total_count.zero? ? 0 : (page - 1) * per_page + 1
  def last_item = [ page * per_page, total_count ].min

  private

  def prepare_scopes
    # These relations already carry the caller's authorization and Group boundary.
    # Wrapping each in a self-table IN query repeats those scans in every filter.
    @thread_scope = @jjaek_scope.reorder(nil)
    @scoped_comments = @comment_scope.reorder(nil)
  end

  def apply_content_section
    case @content_section
    when "group"
      @thread_scope = @thread_scope.where.not(group_id: nil)
    when "comments"
      @thread_scope = @thread_scope.where(id: @scoped_comments.reselect("comments.jjaek_id"))
    end
  end

  def apply_search
    term = @params[:content_q].to_s.strip
    return if term.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    @thread_scope = threads_matching(search_root_ids(pattern), search_comment_root_ids(pattern))
  end

  def search_root_ids(_pattern)
    raise NotImplementedError
  end

  def search_comment_root_ids(_pattern)
    raise NotImplementedError
  end

  def apply_status
    return unless STATUSES.include?(@params[:content_status])
    if @params[:content_status] == "deleted"
      @thread_scope = @thread_scope.where.not(deleted_at: nil)
      return
    end

    matching_roots, matching_comment_root_ids = status_matches(@params[:content_status])
    @thread_scope = threads_matching(matching_roots.reselect("jjaeks.id"), matching_comment_root_ids)
  end

  def status_matches(status)
    case status
    when "active"
      [
        @jjaek_scope.reorder(nil).where(deleted_at: nil, hidden_at: nil),
        @scoped_comments.where(hidden_at: nil).reselect("comments.jjaek_id")
      ]
    when "hidden"
      [
        @jjaek_scope.reorder(nil).where(deleted_at: nil).where.not(hidden_at: nil),
        @scoped_comments.where.not(hidden_at: nil).reselect("comments.jjaek_id")
      ]
    end
  end

  def threads_matching(root_ids, comment_root_ids)
    matching_ids = root_ids.reorder(nil).arel.union(comment_root_ids.reorder(nil).arel)
    @thread_scope.where(Jjaek.arel_table[:id].in(matching_ids))
  end

  def page_sql
    offset = (page - 1) * per_page
    direction = SORT_DIRECTIONS.fetch(@params[:content_sort].to_s, SORT_DIRECTIONS["recent"])

    matching_roots = @thread_scope.reselect("jjaeks.id", "jjaeks.created_at").distinct
    page = Jjaek.from("matching_roots AS jjaeks")
      .joins("LEFT JOIN latest_comments ON latest_comments.jjaek_id = jjaeks.id")
      .select(
        "jjaeks.id AS jjaek_id",
        "GREATEST(jjaeks.created_at, COALESCE(latest_comments.latest_comment_at, jjaeks.created_at)) AS latest_activity_at"
      )
      .order(Arel.sql("latest_activity_at #{direction}, jjaeks.id #{direction}"))
      .limit(per_page)
      .offset(offset)
      .to_sql

    # Materialize once even when sparse/stale test statistics favor nested loops.
    # Aggregate ALL authorized Group comments once, not just the comment that
    # matched search/status, so latest activity and full-thread order agree.
    <<~SQL.squish
      WITH matching_roots AS MATERIALIZED (#{matching_roots.to_sql}),
           latest_comments AS MATERIALIZED (#{latest_comments_sql})
      #{page}
    SQL
  end

  def latest_comments_sql
    @scoped_comments
      .group(:jjaek_id)
      .reselect("comments.jjaek_id", "MAX(comments.created_at) AS latest_comment_at")
      .distinct(false)
      .to_sql
  end

  def normalized_page
    requested = Integer(@params[:all_page], exception: false).to_i
    requested = 1 if requested < 1
    @total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
    [ requested, @total_pages ].min
  end

  def hydrate(rows)
    root_ids = rows.map { |row| row.fetch("jjaek_id").to_i }
    # Page IDs have already passed search/status. Recheck the original access
    # scope here without rerunning the complete thread-selection query.
    roots = @jjaek_scope.reorder(nil).where(id: root_ids).reselect("jjaeks.*")
      .includes(:group, :attached_books, user: { avatar_attachment: :blob })
      .index_by(&:id)
    comments_by_root_id = @scoped_comments.where(jjaek_id: root_ids).reselect("comments.*").distinct
      .includes(user: { avatar_attachment: :blob })
      .order(created_at: :desc, id: :desc)
      .group_by(&:jjaek_id)

    rows.filter_map do |row|
      root = roots[row.fetch("jjaek_id").to_i]
      next unless root

      ContentThread.new(
        root:,
        comments: comments_by_root_id.fetch(root.id, []),
        latest_activity_at: row.fetch("latest_activity_at")
      )
    end
  end

  def connection
    ActiveRecord::Base.connection
  end
end
