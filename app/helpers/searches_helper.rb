module SearchesHelper
  def search_input_value
    return @query unless @tag_mode

    name = @tag || @tag_input
    name.present? ? "##{name}" : ""
  end

  def search_results_params(type: @type, page: nil, scope: @tag_scope)
    if @tag_mode
      { tag: @tag || @tag_input, scope:, group_id: @tag_group&.id, user_id: @tag_user&.id,
        type:, per_page: @per_page, page: }.compact
    else
      { q: @query.presence, type:, per_page: @per_page, page: }.compact
    end
  end

  def tag_scope_label
    return t("unified_search.tag_scopes.group", name: @tag_group.name) if @tag_group

    t("unified_search.tag_scopes.user", name: @tag_user.name)
  end

  def search_user_relationship_labels(user)
    return [] if user.id == current_user.id

    labels = []
    labels << t("relationships.sections.book_friends") if @search_book_friend_ids.include?(user.id)
    labels << t("relationships.sections.following_users") if @search_following_ids.include?(user.id)
    labels << t("relationships.sections.followers") if @search_follower_ids.include?(user.id)
    labels
  end
end
