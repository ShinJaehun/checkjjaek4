module RelationshipsHelper
  def relationship_rows(page)
    partial, locals = case page.tab
    when "received_book_friend_requests"
      [ "book_friend_request_row", { direction: :received } ]
    when "sent_book_friend_requests"
      [ "book_friend_request_row", { direction: :sent } ]
    when "book_friends"
      [ "book_friend_row", {} ]
    when "following_users"
      [ "followee_row", {} ]
    when "followers"
      [ "follower_row", {} ]
    end

    render partial: "relationships/#{partial}", collection: page.records, as: :record, locals: locals
  end

  def relationship_action_params
    @relationship_page.navigation_params.merge(return_to: "relationships")
  end

  def book_friendship_action_params(friendship)
    return {} unless friendship

    { friendship_id: friendship.id, friendship_status: friendship.status }
  end
end
