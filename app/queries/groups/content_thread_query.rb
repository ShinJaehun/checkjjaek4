module Groups
  class ContentThreadQuery < ::GroupContentThreadQuery
    def initialize(group:, jjaek_scope:, comment_scope:, content_section:, params:)
      super(
        jjaek_scope: jjaek_scope.where(group_id: group.id),
        comment_scope: comment_scope.where(jjaek_id: group.jjaeks.select(:id)),
        content_section:,
        params:
      )
    end

    private

    def search_root_ids(pattern)
      authored_roots = @thread_scope.joins(:user)
      matching_names = authored_roots.where("users.name ILIKE ?", pattern)
      content_scope = authored_roots.where(deleted_at: nil)
      searchable_content = content_scope.where(hidden_at: nil)
        .or(content_scope.where.not(hidden_at: nil).where(id: current_group_hidden_ids("Jjaek")))
      matching_content = searchable_content.where("jjaeks.content ILIKE ?", pattern)

      matching_names.or(matching_content).reselect("jjaeks.id")
    end

    def search_comment_root_ids(pattern)
      authored_comments = @scoped_comments.joins(:user)
      matching_names = authored_comments.where("users.name ILIKE ?", pattern)
      searchable_content = authored_comments.where(hidden_at: nil)
        .or(authored_comments.where.not(hidden_at: nil).where(id: current_group_hidden_ids("Comment")))
      matching_content = searchable_content.where("comments.content ILIKE ?", pattern)

      matching_names.or(matching_content).reselect("comments.jjaek_id")
    end

    def current_group_hidden_ids(target_type)
      restored_hide_ids = ModerationAction.action_type_restore
        .where.not(reversal_of_id: nil)
        .select(:reversal_of_id)

      current_hides = ModerationAction.action_type_hide
        .where(target_type:)
        .where.not(id: restored_hide_ids)
        .select("DISTINCT ON (moderation_actions.target_id) moderation_actions.target_id, moderation_actions.moderation_authority")
        .order("moderation_actions.target_id", "moderation_actions.created_at DESC", "moderation_actions.id DESC")

      ModerationAction.from("(#{current_hides.to_sql}) current_hides")
        .where("current_hides.moderation_authority = ?", "group")
        .select("current_hides.target_id")
    end
  end
end
