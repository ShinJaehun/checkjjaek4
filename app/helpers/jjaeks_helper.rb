module JjaeksHelper
  def jjaek_context_label(jjaek)
    t(jjaek_context_translation_key(jjaek), **jjaek_context_translation_options(jjaek))
  end

  def current_user_like_for(jjaek)
    jjaek.likes.find { |like| like.user_id == current_user.id }
  end

  def show_requote_book_link?(jjaek)
    jjaek.book.present? && jjaek.quoted_jjaek.present?
  end

  private

  def jjaek_context_translation_key(jjaek)
    if jjaek.quoted_jjaek.present?
      "jjaeks.contexts.requote_html"
    elsif jjaek.book.present?
      "jjaeks.contexts.book_html"
    elsif jjaek.target_user.present?
      "jjaeks.contexts.profile_html"
    else
      "jjaeks.contexts.general_html"
    end
  end

  def jjaek_context_translation_options(jjaek)
    options = { author_name: jjaek_context_user_link(jjaek.user) }

    if jjaek.quoted_jjaek.present?
      options[:quoted_user_name] = jjaek_context_user_link(jjaek.quoted_jjaek.user)
    elsif jjaek.book.present?
      options[:book_title] = jjaek_context_book_link(jjaek.book)
    elsif jjaek.target_user.present?
      options[:target_user_name] = jjaek_context_user_link(jjaek.target_user)
    end

    options
  end

  def jjaek_context_user_link(user)
    link_to(user.name, user_path(user), class: "font-semibold text-stone-900 hover:text-stone-700")
  end

  def jjaek_context_book_link(book)
    link_to(book.title, book_path(book), class: "font-semibold text-stone-900 hover:text-stone-700")
  end
end
