module Admin
  class GroupContentThreadQuery
    PER_PAGE = InventoryPage::PER_PAGE
    STATUSES = %w[active hidden deleted].freeze
    SORT_DIRECTIONS = { "recent" => "DESC", "oldest" => "ASC" }.freeze
    ContentThread = Struct.new(:root, :comments, :latest_activity_at, keyword_init: true)

    attr_reader :records, :page, :total_count

    def initialize(jjaek_scope:, comment_scope:, content_section:, params:)
      @jjaek_scope = jjaek_scope
      @comment_scope = comment_scope
      @content_section = content_section
      @params = params
    end

    def call
      prepare_scopes
      apply_content_section
      apply_search
      apply_status
      @total_count = @thread_scope.count
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

    def first_item = total_count.zero? ? 0 : (page - 1) * PER_PAGE + 1
    def last_item = [ page * PER_PAGE, total_count ].min

    private

    def prepare_scopes
      @thread_scope = Jjaek.where(id: @jjaek_scope.reorder(nil).select("jjaeks.id"))
      @scoped_comments = Comment.where(id: @comment_scope.reorder(nil).select("comments.id"))
    end

    def apply_content_section
      case @content_section
      when "general"
        @thread_scope = non_requotes(@thread_scope).where(book_id: nil)
      when "book"
        @thread_scope = non_requotes(@thread_scope).where.not(book_id: nil)
      when "comments"
        @thread_scope = @thread_scope.where(id: @scoped_comments.select(:jjaek_id))
      end
    end

    def apply_search
      term = @params[:content_q].to_s.strip
      return if term.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      matching_root_ids = @thread_scope.joins(:user).where(
        "jjaeks.content ILIKE :term OR users.name ILIKE :term OR users.email ILIKE :term",
        term: pattern
      ).select("jjaeks.id")
      matching_comment_root_ids = @scoped_comments.joins(:user).where(
        "comments.content ILIKE :term OR users.name ILIKE :term OR users.email ILIKE :term",
        term: pattern
      ).select("comments.jjaek_id")

      @thread_scope = threads_matching(matching_root_ids, matching_comment_root_ids)
    end

    def apply_status
      return unless STATUSES.include?(@params[:content_status])

      matching_root_ids, matching_comment_root_ids = status_matches(@params[:content_status])
      @thread_scope = threads_matching(matching_root_ids, matching_comment_root_ids)
    end

    def status_matches(status)
      case status
      when "active"
        [
          @thread_scope.where(deleted_at: nil, hidden_at: nil).select(:id),
          @scoped_comments.where(hidden_at: nil).select(:jjaek_id)
        ]
      when "hidden"
        [
          @thread_scope.where(deleted_at: nil).where.not(hidden_at: nil).select(:id),
          @scoped_comments.where.not(hidden_at: nil).select(:jjaek_id)
        ]
      when "deleted"
        [
          @thread_scope.where.not(deleted_at: nil).select(:id),
          @scoped_comments.none.select(:jjaek_id)
        ]
      end
    end

    def threads_matching(root_ids, comment_root_ids)
      @thread_scope.where(id: root_ids).or(@thread_scope.where(id: comment_root_ids))
    end

    def non_requotes(scope)
      scope.where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
    end

    def page_sql
      offset = (page - 1) * PER_PAGE
      direction = SORT_DIRECTIONS.fetch(@params[:content_sort].to_s, SORT_DIRECTIONS["recent"])

      @thread_scope.reorder(nil)
        .joins("LEFT JOIN (#{latest_comments_sql}) latest_comments ON latest_comments.jjaek_id = jjaeks.id")
        .select(
          "jjaeks.id AS jjaek_id",
          "GREATEST(jjaeks.created_at, COALESCE(latest_comments.latest_comment_at, jjaeks.created_at)) AS latest_activity_at"
        )
        .order(Arel.sql("latest_activity_at #{direction}, jjaeks.id #{direction}"))
        .limit(PER_PAGE)
        .offset(offset)
        .to_sql
    end

    def latest_comments_sql
      @scoped_comments.reorder(nil)
        .group(:jjaek_id)
        .select(:jjaek_id, "MAX(comments.created_at) AS latest_comment_at")
        .to_sql
    end

    def normalized_page
      requested = Integer(@params[:all_page], exception: false).to_i
      requested = 1 if requested < 1
      @total_pages = [ (total_count.to_f / PER_PAGE).ceil, 1 ].max
      [ requested, @total_pages ].min
    end

    def hydrate(rows)
      root_ids = rows.map { |row| row.fetch("jjaek_id").to_i }
      roots = @thread_scope.where(id: root_ids)
        .includes(:user, :book)
        .index_by(&:id)
      comments_by_root_id = @scoped_comments.where(jjaek_id: root_ids)
        .includes(:user)
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
end
