class RelationshipsController < ApplicationController
  def index
    @received_book_friend_requests = current_user.received_book_friendships.pending.includes(:requester)
    @sent_book_friend_requests = current_user.requested_book_friendships.pending.includes(:addressee)
    @book_friends = User.where(id: BookFriendship.connected_ids_for(current_user)).order(:name)
    @following_users = current_user.followees.order(:name)
    @followers = current_user.followers.order(:name)
  end
end
