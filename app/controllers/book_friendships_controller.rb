class BookFriendshipsController < ApplicationController
  include RelationshipManagement

  before_action :set_user

  def create
    friendship = current_user.requested_book_friendships.build(addressee: @user)
    authorize friendship

    if BookFriendship.between(current_user, @user)
      redirect_to redirect_target, alert: t("book_friendships.alerts.already_exists")
      return
    end

    if friendship.save
      Notification.notify_book_friendship_requested(friendship)
      redirect_to redirect_target, notice: t("book_friendships.notices.created")
    else
      redirect_to redirect_target, alert: friendship.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to redirect_target, alert: t("book_friendships.alerts.already_exists")
  end

  def update
    friendship = current_user.received_book_friendships.find_by(requester: @user)
    unless friendship
      redirect_to redirect_target, alert: t("book_friendships.alerts.stale_action"), status: :see_other
      return
    end

    authorize friendship, :accept?

    friendship.accepted!
    Notification.notify_book_friendship_accepted(friendship)

    if params[:return_to] == "relationships"
      render_relationships_change(notice: t("book_friendships.notices.accepted"))
    else
      redirect_to redirect_target, notice: t("book_friendships.notices.accepted")
    end
  end

  def destroy
    friendship = BookFriendship.between(current_user, @user)

    unless friendship
      redirect_to redirect_target, alert: t("book_friendships.alerts.not_found")
      return
    end

    authorize friendship
    notice_key = destroy_notice_key(friendship)
    friendship.destroy!

    if params[:return_to] == "relationships"
      render_relationships_change(notice: t("book_friendships.notices.#{notice_key}"))
    else
      redirect_to redirect_target, notice: t("book_friendships.notices.#{notice_key}")
    end
  end

  private

  def set_user
    @user = User.find_by_public_param!(params[:user_id])
  end

  def redirect_target
    params[:return_to] == "relationships" ? relationships_return_path : user_path(@user)
  end

  def destroy_notice_key(friendship)
    return :removed if friendship.accepted?
    return :cancelled if friendship.requester_id == current_user.id

    :rejected
  end
end
