module Admin
  class GroupContentThreadQuery < ::GroupContentThreadQuery
    private

    def apply_content_section
      super
      if @content_section == "group"
        @thread_scope = @thread_scope.where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
      elsif @content_section == "requote"
        @thread_scope = @thread_scope.where.not(quoted_jjaek_id: nil)
          .or(@thread_scope.where.not(quoted_source_deleted_at: nil))
      end
    end

    def search_root_ids(pattern)
      @thread_scope.joins(:user).where(
        "jjaeks.content ILIKE :term OR users.name ILIKE :term OR users.email ILIKE :term",
        term: pattern
      ).select("jjaeks.id")
    end

    def search_comment_root_ids(pattern)
      @scoped_comments.joins(:user).where(
        "comments.content ILIKE :term OR users.name ILIKE :term OR users.email ILIKE :term",
        term: pattern
      ).select("comments.jjaek_id")
    end
  end
end
