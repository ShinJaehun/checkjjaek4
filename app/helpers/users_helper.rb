module UsersHelper
  def profile_follow_button_options(user)
    if current_user.follows?(user)
      {
        label: t("users.actions.unfollow"),
        path: user_follow_path(user),
        method: :delete,
        class_name: secondary_profile_action_class
      }
    else
      {
        label: t("users.actions.follow"),
        path: user_follow_path(user),
        class_name: primary_profile_action_class
      }
    end
  end

  def profile_book_friend_button_options(user, book_friendship)
    if book_friendship&.accepted?
      {
        label: t("users.actions.remove_book_friend"),
        path: user_book_friendship_path(user),
        method: :delete,
        class_name: secondary_profile_action_class
      }
    elsif book_friendship&.pending? && book_friendship.requester_id == current_user.id
      {
        label: t("users.actions.cancel_book_friend_request"),
        path: user_book_friendship_path(user),
        method: :delete,
        class_name: secondary_profile_action_class
      }
    elsif book_friendship&.pending? && book_friendship.addressee_id == current_user.id
      {
        label: t("users.actions.accept_book_friend"),
        path: user_book_friendship_path(user),
        method: :patch,
        class_name: primary_profile_action_class
      }
    else
      {
        label: t("users.actions.request_book_friend"),
        path: user_book_friendship_path(user),
        class_name: secondary_profile_action_class
      }
    end
  end

  private

  def primary_profile_action_class
    "rounded-full bg-stone-900 px-4 py-2 text-sm font-medium text-stone-50"
  end

  def secondary_profile_action_class
    "rounded-full border border-stone-300 px-4 py-2 text-sm font-medium text-stone-700"
  end
end
