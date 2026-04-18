module PostsHelper
  def like_button_for(post)
    current_like = post.likes.find { |like| like.user_id == current_user.id }

    if current_like
      button_to t("likes.actions.unlike"), post_like_path(post), method: :delete, class: "text-sm font-medium text-stone-700"
    else
      button_to t("likes.actions.like"), post_like_path(post), class: "text-sm font-medium text-stone-700"
    end
  end
end
