module GroupShowContext
  private

  def prepare_group_show_context
    active_member_scope = @group.active_group_memberships.where.not(user_id: @group.group_admin_id)
    @member_preview = active_member_scope.includes(user: { avatar_attachment: :blob }).order(:created_at, :id).limit(5).map(&:user)
    @active_member_count = active_member_scope.count
    @membership = @group.group_memberships.find_by(user: current_user)
    @group_member_ban = @group.group_member_bans.find_by(user: current_user)
    @current_group_ban_action = @group_member_ban&.current_ban_action
    @current_operation_suspension = @group.current_operation_suspension_action
    @current_activity_suspension = @membership&.current_activity_suspension_action if @membership&.activity_suspended?
    prepare_group_jjaek_context
  end

  def prepare_group_jjaek_context
    group_policy = policy(@group)
    @can_read_group_jjaeks = group_policy.read_jjaeks?
    @jjaeks = if @can_read_group_jjaeks
      policy_scope(
        @group.jjaeks,
        policy_scope_class: JjaekPolicy::GroupContentScope
      ).includes(:book, :group, :likes, :comments, :moderation_actions, user: { avatar_attachment: :blob }, quoted_jjaek: [ { user: { avatar_attachment: :blob } }, :book, :group ]).recent
    else
      Jjaek.none
    end
    @feed_page = FeedPage.new(jjaeks: @jjaeks, cursor: params[:cursor])
    @feed_next_url = group_path(@group, cursor: @feed_page.next_cursor) if @feed_page.next_cursor
    @jjaeks = @feed_page.items
    prepare_current_reading_states_for(@jjaeks)
    prepare_visible_requote_counts_for(@jjaeks)
  end
end
