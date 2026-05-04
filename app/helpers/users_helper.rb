module UsersHelper
  BOOKSHELF_TAB_CLASSES_BY_COLOR_KEY = {
    "stone" => {
      selected: "border-stone-900 bg-stone-900 text-white",
      unselected: "border-stone-200 bg-stone-50 text-stone-700 hover:border-stone-400 hover:text-stone-900",
      count_selected: "text-stone-200",
      count_unselected: "text-stone-400"
    },
    "red" => {
      selected: "border-red-700 bg-red-600 text-white",
      unselected: "border-red-200 bg-red-50 text-red-700 hover:border-red-300 hover:text-red-900",
      count_selected: "text-red-100",
      count_unselected: "text-red-400"
    },
    "orange" => {
      selected: "border-orange-700 bg-orange-500 text-white",
      unselected: "border-orange-200 bg-orange-50 text-orange-700 hover:border-orange-300 hover:text-orange-900",
      count_selected: "text-orange-100",
      count_unselected: "text-orange-400"
    },
    "yellow" => {
      selected: "border-yellow-600 bg-yellow-400 text-yellow-950",
      unselected: "border-yellow-200 bg-yellow-50 text-yellow-800 hover:border-yellow-300 hover:text-yellow-950",
      count_selected: "text-yellow-800",
      count_unselected: "text-yellow-500"
    },
    "green" => {
      selected: "border-green-700 bg-green-600 text-white",
      unselected: "border-green-200 bg-green-50 text-green-700 hover:border-green-300 hover:text-green-900",
      count_selected: "text-green-100",
      count_unselected: "text-green-400"
    },
    "blue" => {
      selected: "border-blue-700 bg-blue-600 text-white",
      unselected: "border-blue-200 bg-blue-50 text-blue-700 hover:border-blue-300 hover:text-blue-900",
      count_selected: "text-blue-100",
      count_unselected: "text-blue-400"
    },
    "purple" => {
      selected: "border-purple-700 bg-purple-600 text-white",
      unselected: "border-purple-200 bg-purple-50 text-purple-700 hover:border-purple-300 hover:text-purple-900",
      count_selected: "text-purple-100",
      count_unselected: "text-purple-400"
    },
    "pink" => {
      selected: "border-pink-700 bg-pink-600 text-white",
      unselected: "border-pink-200 bg-pink-50 text-pink-700 hover:border-pink-300 hover:text-pink-900",
      count_selected: "text-pink-100",
      count_unselected: "text-pink-400"
    }
  }.freeze

  def bookshelf_tab_class(bookshelf, selected:)
    bookshelf_color_palette(bookshelf).fetch(selected ? :selected : :unselected)
  end

  def bookshelf_tab_count_class(bookshelf, selected:)
    bookshelf_color_palette(bookshelf).fetch(selected ? :count_selected : :count_unselected)
  end

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

  def bookshelf_color_palette(bookshelf)
    BOOKSHELF_TAB_CLASSES_BY_COLOR_KEY.fetch(bookshelf.color_key, BOOKSHELF_TAB_CLASSES_BY_COLOR_KEY.fetch("stone"))
  end

  def primary_profile_action_class
    "rounded-full bg-stone-900 px-4 py-2 text-sm font-medium text-stone-50"
  end

  def secondary_profile_action_class
    "rounded-full border border-stone-300 px-4 py-2 text-sm font-medium text-stone-700"
  end
end
