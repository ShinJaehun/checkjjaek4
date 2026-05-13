class BookFriendshipsController < ApplicationController
  before_action :set_user

  def create
    friendship = current_user.requested_book_friendships.find_or_initialize_by(addressee: @user)
    authorize friendship

    should_notify = friendship.new_record?

    if friendship.persisted? || friendship.save
      Notification.notify_book_friendship_requested(friendship) if should_notify
      redirect_to redirect_target, notice: t("book_friendships.notices.created")
    else
      redirect_to redirect_target, alert: friendship.errors.full_messages.to_sentence
    end
  end

  def update
    friendship = current_user.received_book_friendships.find_by!(requester: @user)
    authorize friendship, :accept?

    friendship.accepted!

    if params[:return_to] == "relationships"
      @received_book_friend_requests = current_user.received_book_friendships.pending.includes(:requester)
      @book_friends = User.where(id: BookFriendship.connected_ids_for(current_user)).order(:name)
      flash.now[:notice] = t("book_friendships.notices.accepted")

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to redirect_target, notice: t("book_friendships.notices.accepted") }
      end
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

    if params[:return_to] == "relationships" && notice_key.in?(%i[cancelled rejected])
      prepare_relationships_section(notice_key)
      flash.now[:notice] = t("book_friendships.notices.#{notice_key}")

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to redirect_target, notice: t("book_friendships.notices.#{notice_key}") }
      end
    else
      redirect_to redirect_target, notice: t("book_friendships.notices.#{notice_key}")
    end
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def redirect_target
    params[:return_to] == "relationships" ? relationships_path : user_path(@user)
  end

  def destroy_notice_key(friendship)
    return :removed if friendship.accepted?
    return :cancelled if friendship.requester_id == current_user.id

    :rejected
  end

  def prepare_relationships_section(notice_key)
    if notice_key == :cancelled
      @relationship_section_id = "sent-book-friend-requests"
      @relationship_section_title = t("relationships.sections.sent_book_friend_requests")
      @relationship_section_collection = current_user.requested_book_friendships.pending.includes(:addressee)
      @relationship_section_row_locals = { direction: :sent }
      @relationship_section_empty_message = t("relationships.empty.sent_book_friend_requests")
    else
      @relationship_section_id = "received-book-friend-requests"
      @relationship_section_class = "scroll-mt-6 space-y-4"
      @relationship_section_title = t("relationships.sections.received_book_friend_requests")
      @relationship_section_collection = current_user.received_book_friendships.pending.includes(:requester)
      @relationship_section_row_locals = { direction: :received }
      @relationship_section_empty_message = t("relationships.empty.received_book_friend_requests")
    end

    @relationship_section_row_partial = "relationships/book_friend_request_row"
  end
end
