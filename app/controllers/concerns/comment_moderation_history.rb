module CommentModerationHistory
  private

  def prepare_comment_moderation_histories(comments)
    @comment_moderation_histories = {}
    comments.each do |record|
      comment_policy = policy(record)
      next unless comment_policy.view_admin_inventory? || comment_policy.view_group_moderation_history?

      actions = record.moderation_actions.where(action_type: %i[hide restore])
      actions = actions.where(moderation_authority: "group") if comment_policy.view_group_moderation_history?
      @comment_moderation_histories[record.id] = actions.includes(:actor).order(created_at: :asc, id: :asc).to_a
    end
  end
end
