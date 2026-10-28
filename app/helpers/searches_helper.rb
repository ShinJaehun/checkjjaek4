module SearchesHelper
  def search_results_params(type: @type, page: nil)
    { q: @query.presence, type: type, per_page: @per_page, page: page }.compact
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
