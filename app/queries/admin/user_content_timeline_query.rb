module Admin
  class UserContentTimelineQuery
    LOCATIONS = %w[personal group].freeze
    STATUSES = %w[active hidden deleted].freeze
    SORT_DIRECTIONS = { "recent" => "DESC", "oldest" => "ASC" }.freeze
    TimelineItem = Struct.new(:record_type, :record, keyword_init: true)

    attr_reader :records, :page, :per_page, :total_count

    def initialize(jjaek_scope:, comment_scope:, content_section:, params:)
      @jjaek_scope = jjaek_scope
      @comment_scope = comment_scope
      @content_section = content_section
      @params = params
      @per_page = InventoryPage.normalize_per_page(params[:per_page])
    end

    def call
      activity_counts
      apply_content_section
      @total_count = connection.select_value(count_sql).to_i
      @page = normalized_page
      rows = connection.select_all(page_sql)
      @records = hydrate(rows)
      self
    end

    def activity_counts
      return @activity_counts if @activity_counts

      apply_filters
      kind_sql = <<~SQL.squish
        CASE
          WHEN jjaeks.quoted_jjaek_id IS NOT NULL OR jjaeks.quoted_source_deleted_at IS NOT NULL THEN 'requote'
          WHEN jjaeks.group_id IS NOT NULL THEN 'group'
          ELSE 'general'
        END
      SQL
      @activity_counts = { "general" => 0, "group" => 0, "requote" => 0 }
        .merge(@jjaek_scope.reorder(nil).group(Arel.sql(kind_sql)).count)
      @activity_counts["comments"] = @comment_scope.count
      @activity_counts
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

    def apply_filters
      apply_search
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
        @jjaek_scope = @jjaek_scope.where(group_id: nil, quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
        @comment_scope = @comment_scope.none
      when "group"
        @jjaek_scope = @jjaek_scope.where.not(group_id: nil).where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
        @comment_scope = @comment_scope.none
      when "requote"
        @jjaek_scope = @jjaek_scope.where.not(quoted_jjaek_id: nil)
          .or(@jjaek_scope.where.not(quoted_source_deleted_at: nil))
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

      case @params[:status]
      when "active"
        @jjaek_scope = @jjaek_scope.where(deleted_at: nil, hidden_at: nil)
        @comment_scope = @comment_scope.where(hidden_at: nil)
      when "hidden"
        @jjaek_scope = @jjaek_scope.where(deleted_at: nil).where.not(hidden_at: nil)
        @comment_scope = @comment_scope.where.not(hidden_at: nil)
      when "deleted"
        @jjaek_scope = @jjaek_scope.where.not(deleted_at: nil)
        @comment_scope = @comment_scope.none
      end
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
      offset = (page - 1) * per_page
      direction = SORT_DIRECTIONS.fetch(@params[:sort].to_s, SORT_DIRECTIONS["recent"])
      <<~SQL.squish
        SELECT record_type, record_id, created_at
        FROM (#{union_sql}) admin_user_content_timeline
        ORDER BY created_at #{direction}, record_type #{direction}, record_id #{direction}
        LIMIT #{per_page} OFFSET #{offset}
      SQL
    end

    def normalized_page
      requested = Integer(@params[:all_page], exception: false).to_i
      requested = 1 if requested < 1
      @total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
      [ requested, @total_pages ].min
    end

    def hydrate(rows)
      jjaek_ids = row_ids(rows, "Jjaek")
      comment_ids = row_ids(rows, "Comment")
      jjaeks = @jjaek_scope.where(id: jjaek_ids)
        .includes(:group, :attached_books)
        .index_by(&:id)
      comments = @comment_scope.where(id: comment_ids)
        .includes(jjaek: %i[user group])
        .index_by(&:id)

      rows.filter_map do |row|
        record_type = row.fetch("record_type")
        records = record_type == "Jjaek" ? jjaeks : comments
        record = records[row.fetch("record_id").to_i]
        TimelineItem.new(record_type:, record:) if record
      end
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
