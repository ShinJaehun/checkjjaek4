module Admin
  class GroupContentThreadQuery < ::GroupContentThreadQuery
    private

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
