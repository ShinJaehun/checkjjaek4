class RelationshipsController < ApplicationController
  def index
    @received_book_friend_requests = current_user.received_book_friendships.pending.includes(requester: { avatar_attachment: :blob })
    @sent_book_friend_requests = current_user.requested_book_friendships.pending.includes(addressee: { avatar_attachment: :blob })
    @book_friends = User.where(id: BookFriendship.connected_ids_for(current_user)).includes(avatar_attachment: :blob).order(:name)
    @following_users = current_user.followees.includes(avatar_attachment: :blob).order(:name)
    @followers = current_user.followers.includes(avatar_attachment: :blob).order(:name)
  end
end
