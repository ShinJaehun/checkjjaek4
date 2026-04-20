class BookFriendshipsController < ApplicationController
  before_action :set_user

  def create
    friendship = current_user.requested_book_friendships.find_or_initialize_by(addressee: @user)
    authorize friendship

    if friendship.persisted? || friendship.save
      redirect_to user_path(@user), notice: t("book_friendships.notices.created")
    else
      redirect_to user_path(@user), alert: friendship.errors.full_messages.to_sentence
    end
  end

  def update
    friendship = current_user.received_book_friendships.find_by!(requester: @user)
    authorize friendship, :accept?

    friendship.accepted!
    redirect_to user_path(@user), notice: t("book_friendships.notices.accepted")
  end

  def destroy
    friendship = BookFriendship.between(current_user, @user)

    unless friendship
      redirect_to user_path(@user), alert: t("book_friendships.alerts.not_found")
      return
    end

    authorize friendship
    friendship.destroy!
    redirect_to user_path(@user), notice: t("book_friendships.notices.destroyed")
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end
end
