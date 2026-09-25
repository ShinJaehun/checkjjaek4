module Admin
  class LatestContentActivityQuery
    Activity = Struct.new(:record_type, :record, :kind, keyword_init: true) do
      def comment? = record_type == "Comment"

      delegate :created_at, to: :record
    end

    def initialize(owner_type:, owner_ids:)
      @owner_type = owner_type.to_sym
      @owner_ids = owner_ids
    end

    def call
      return {} if @owner_ids.empty?

      rows = connection.select_all(latest_rows_sql)
      hydrate(rows)
    end

    private

    def latest_rows_sql
      <<~SQL.squish
        SELECT DISTINCT ON (owner_id) owner_id, record_type, record_id, created_at
        FROM (#{activity_rows_sql}) admin_latest_content_activities
        ORDER BY owner_id, created_at DESC, record_type DESC, record_id DESC
      SQL
    end

    def activity_rows_sql
      [ jjaek_rows.to_sql, comment_rows.to_sql ].join(" UNION ALL ")
    end

    def jjaek_rows
      scope = Jjaek.where(owner_column => @owner_ids)
      scope.select(
        "jjaeks.#{owner_column} AS owner_id",
        "'Jjaek' AS record_type",
        "jjaeks.id AS record_id",
        "jjaeks.created_at AS created_at"
      )
    end

    def comment_rows
      if @owner_type == :user
        Comment.where(user_id: @owner_ids).select(
          "comments.user_id AS owner_id",
          "'Comment' AS record_type",
          "comments.id AS record_id",
          "comments.created_at AS created_at"
        )
      else
        Comment.joins(:jjaek).where(jjaeks: { group_id: @owner_ids }).select(
          "jjaeks.group_id AS owner_id",
          "'Comment' AS record_type",
          "comments.id AS record_id",
          "comments.created_at AS created_at"
        )
      end
    end

    def owner_column
      return :user_id if @owner_type == :user
      return :group_id if @owner_type == :group

      raise ArgumentError, "owner_type must be :user or :group"
    end

    def hydrate(rows)
      jjaeks = Jjaek.where(id: row_ids(rows, "Jjaek")).index_by(&:id)
      comments = Comment.where(id: row_ids(rows, "Comment")).includes(:jjaek).index_by(&:id)

      rows.each_with_object({}) do |row, activities|
        record_type = row.fetch("record_type")
        records = record_type == "Jjaek" ? jjaeks : comments
        record = records[row.fetch("record_id").to_i]
        next unless record

        activities[row.fetch("owner_id").to_i] = Activity.new(
          record_type:,
          record:,
          kind: content_kind(record_type, record)
        )
      end
    end

    def content_kind(record_type, record)
      return "comments" if record_type == "Comment"
      return "requote" if record.requote?
      return "group_book" if record.group_id.present? && record.book_id.present?
      return "group_general" if record.group_id.present?
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
