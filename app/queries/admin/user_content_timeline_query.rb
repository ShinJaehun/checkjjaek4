module Admin
  class UserContentTimelineQuery
    PER_PAGE = InventoryPage::PER_PAGE
    LOCATIONS = %w[personal group].freeze
    STATUSES = %w[active deleted].freeze
    SORT_DIRECTIONS = { "recent" => "DESC", "oldest" => "ASC" }.freeze
    TimelineItem = Struct.new(:record_type, :record, :kind, keyword_init: true)

    attr_reader :records, :page, :total_count

    def initialize(jjaek_scope:, comment_scope:, content_section:, params:)
      @jjaek_scope = jjaek_scope
      @comment_scope = comment_scope
      @content_section = content_section
      @params = params
    end

    def call
      apply_filters
      @total_count = connection.select_value(count_sql).to_i
      @page = normalized_page
      rows = connection.select_all(page_sql)
      @records = hydrate(rows)
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

    def apply_filters
      apply_search
      apply_content_section
      apply_location
      apply_status
    end

    def apply_search
      term = @params[:q].to_s.strip
      return if term.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      @jjaek_scope = @jjaek_scope.where("jjaeks.content ILIKE :term", term: pattern)
      @comment_scope = @comment_scope.where("comments.content ILIKE :term", term: pattern)
    end

    def apply_content_section
      case @content_section
      when "general"
        @jjaek_scope = non_requotes(@jjaek_scope).where(book_id: nil)
        @comment_scope = @comment_scope.none
      when "book"
        @jjaek_scope = non_requotes(@jjaek_scope).where.not(book_id: nil)
        @comment_scope = @comment_scope.none
      when "requote"
        @jjaek_scope = requotes(@jjaek_scope)
        @comment_scope = @comment_scope.none
      when "comments"
        @jjaek_scope = @jjaek_scope.none
      end
    end

    def apply_location
      return unless LOCATIONS.include?(@params[:location])

      if @params[:location] == "personal"
        @jjaek_scope = @jjaek_scope.where(group_id: nil)
        @comment_scope = @comment_scope.joins(:jjaek).where(jjaeks: { group_id: nil })
      else
        @jjaek_scope = @jjaek_scope.where.not(group_id: nil)
        @comment_scope = @comment_scope.joins(:jjaek).where.not(jjaeks: { group_id: nil })
      end
    end

    def apply_status
      return unless STATUSES.include?(@params[:status])

      if @params[:status] == "active"
        @jjaek_scope = @jjaek_scope.where(deleted_at: nil)
      else
        @jjaek_scope = @jjaek_scope.where.not(deleted_at: nil)
        @comment_scope = @comment_scope.none
      end
    end

    def non_requotes(scope)
      scope.where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
    end

    def requotes(scope)
      scope.where.not(quoted_jjaek_id: nil)
        .or(scope.where.not(quoted_source_deleted_at: nil))
    end

    def union_sql
      @union_sql ||= [ jjaek_rows.to_sql, comment_rows.to_sql ].join(" UNION ALL ")
    end

    def jjaek_rows
      @jjaek_scope.reorder(nil).select(
        "'Jjaek' AS record_type",
        "jjaeks.id AS record_id",
        "jjaeks.created_at AS created_at"
      )
    end

    def comment_rows
      @comment_scope.reorder(nil).select(
        "'Comment' AS record_type",
        "comments.id AS record_id",
        "comments.created_at AS created_at"
      )
    end

    def count_sql
      "SELECT COUNT(*) FROM (#{union_sql}) admin_user_content_timeline"
    end

    def page_sql
      offset = (page - 1) * PER_PAGE
      direction = SORT_DIRECTIONS.fetch(@params[:sort].to_s, SORT_DIRECTIONS["recent"])
      <<~SQL.squish
        SELECT record_type, record_id, created_at
        FROM (#{union_sql}) admin_user_content_timeline
        ORDER BY created_at #{direction}, record_type #{direction}, record_id #{direction}
        LIMIT #{PER_PAGE} OFFSET #{offset}
      SQL
    end

    def normalized_page
      requested = Integer(@params[:all_page], exception: false).to_i
      requested = 1 if requested < 1
      @total_pages = [ (total_count.to_f / PER_PAGE).ceil, 1 ].max
      [ requested, @total_pages ].min
    end

    def hydrate(rows)
      jjaek_ids = row_ids(rows, "Jjaek")
      comment_ids = row_ids(rows, "Comment")
      jjaeks = @jjaek_scope.where(id: jjaek_ids)
        .includes(:group, :target_user, :book, quoted_jjaek: :user)
        .index_by(&:id)
      comments = @comment_scope.where(id: comment_ids)
        .includes(jjaek: %i[user group])
        .index_by(&:id)

      rows.filter_map do |row|
        record_type = row.fetch("record_type")
        records = record_type == "Jjaek" ? jjaeks : comments
        record = records[row.fetch("record_id").to_i]
        TimelineItem.new(record_type:, record:, kind: content_kind(record_type, record)) if record
      end
    end

    def content_kind(record_type, record)
      return "comments" if record_type == "Comment"
      return "requote" if record.requote?
      return "book" if record.book_id.present?

      "general"
    end

    def row_ids(rows, record_type)
      rows.filter_map do |row|
        row.fetch("record_id").to_i if row.fetch("record_type") == record_type
      end
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
