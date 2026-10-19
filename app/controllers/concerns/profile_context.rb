module ProfileContext
  private

  def prepare_profile_context
    profile_policy = policy(@user)

    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    @invitable_private_groups = ProfileInvitablePrivateGroupsQuery.new(actor: current_user, target: @user).call
    @cancelable_private_group_invitations = ProfileCancelablePrivateGroupInvitationsQuery.new(actor: current_user, target: @user).call
    prepare_profile_bookshelf(profile_policy)
    prepare_profile_book_activities
    prepare_profile_jjaeks(profile_policy)
    prepare_profile_activity_items
  end

  def prepare_profile_bookshelf(profile_policy)
    @show_bookshelf = profile_policy.show_profile_bookshelf?
    @show_profile_bookshelf_status = profile_policy.show_profile_bookshelf_status?
    @show_library_link = profile_policy.show_library?

    return unless @show_bookshelf

    visible_entries = policy_scope(@user.bookshelf_entries, policy_scope_class: BookshelfEntryPolicy::ProfileScope)
    @profile_public_bookshelf_entries = profile_summary_bookshelf_entries(visible_entries)
  end

  def profile_summary_bookshelf_entries(visible_entries)
    visible_entries.joins(:bookshelf).profile_sorted("recent")
  end

  def prepare_profile_jjaeks(profile_policy)
    @show_jjaeks = profile_policy.show_profile_jjaeks?
    @jjaeks =
      if @show_jjaeks
        resolve_profile_jjaeks
      else
        Jjaek.none
      end
    prepare_current_reading_states_for(@jjaeks)
    prepare_visible_requote_counts_for(@jjaeks)
  end

  def prepare_profile_book_activities
    @book_activities = policy_scope(
      @user.book_activities,
      policy_scope_class: BookActivityPolicy::ProfileScope
    )
      .includes(:book, user: { avatar_attachment: :blob })
      .recent
  end

  def resolve_profile_jjaeks
    policy_scope(
      @user.jjaeks,
      policy_scope_class: JjaekPolicy::ProfileScope
    ).includes(:book, :group, :likes, :comments, :moderation_actions, user: { avatar_attachment: :blob }, target_user: { avatar_attachment: :blob }, quoted_jjaek: [ { user: { avatar_attachment: :blob } }, :book, :group ]).recent
  end

  def prepare_profile_activity_items
    @profile_activity_items = (@jjaeks.to_a + @book_activities.to_a).sort_by(&:created_at).reverse
    @show_profile_activity = @show_jjaeks || current_user == @user || @profile_activity_items.any?
  end
end
