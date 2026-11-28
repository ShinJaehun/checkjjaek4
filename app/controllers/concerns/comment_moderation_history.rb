module CommentModerationHistory
  private

  def prepare_comment_moderation_histories(comments)
    @comment_moderation_histories = {}
    platform_comment_ids = []
    group_comment_ids = []
    comments.each do |record|
      comment_policy = policy(record)
      if comment_policy.view_admin_inventory?
        platform_comment_ids << record.id
      elsif comment_policy.view_group_moderation_history?
        group_comment_ids << record.id
      end
    end
    return if platform_comment_ids.empty? && group_comment_ids.empty?

    actions = ModerationAction.where(target_type: "Comment", action_type: %i[hide restore])
    authorized_actions = actions.where(target_id: platform_comment_ids)
      .or(actions.where(target_id: group_comment_ids, moderation_authority: "group"))
    @comment_moderation_histories = authorized_actions.includes(:actor).order(:created_at, :id).group_by(&:target_id)
  end
end
