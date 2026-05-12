module JjaeksHelper
  def jjaek_context_label(jjaek)
    translation_key = jjaek_context_translation_key(jjaek)
    return if translation_key.blank?

    t(translation_key, **jjaek_context_translation_options(jjaek))
  end

  def current_user_like_for(jjaek)
    jjaek.likes.find { |like| like.user_id == current_user.id }
  end

  def show_requote_book_link?(jjaek)
    jjaek.book.present? && jjaek.quoted_jjaek.present?
  end

  def visible_requote_count_for(jjaek)
    return 0 if jjaek.requote?

    @visible_requote_counts_by_jjaek_id.to_h.fetch(jjaek.id, 0)
  end

  def jjaek_edited?(jjaek)
    return false if jjaek.created_at.blank? || jjaek.updated_at.blank?

    jjaek.updated_at > jjaek.created_at + 1.second
  end

  def comments_panel_dom_id(jjaek, context: :detail)
    case context.to_sym
    when :detail
      dom_id(jjaek, :comments_panel)
    else
      raise ArgumentError, "Unsupported comments panel context: #{context}"
    end
  end

  private

  def jjaek_context_translation_key(jjaek)
    if jjaek.quoted_source_deleted?
      "jjaeks.contexts.deleted_requote_html"
    elsif jjaek.quoted_jjaek.present?
      "jjaeks.contexts.requote_html"
    elsif jjaek.book.present?
      "jjaeks.contexts.book_html"
    elsif profile_context_label?(jjaek)
      "jjaeks.contexts.profile_html"
    else
      "jjaeks.contexts.general_html"
    end
  end

  def jjaek_context_translation_options(jjaek)
    options = { author_name: jjaek_context_user_link(jjaek.user) }

    if jjaek.quoted_jjaek.present?
      options[:quoted_user_name] = jjaek_context_user_link(jjaek.quoted_jjaek.user)
      options[:quoted_context_label] = jjaek.quoted_jjaek.book.present? ? t("jjaeks.contexts.quoted_book") : t("jjaeks.contexts.quoted_general")
    elsif jjaek.book.present?
      options[:book_title] = jjaek_context_book_link(jjaek.book)
    elsif profile_context_label?(jjaek)
      options[:target_user_name] = jjaek_context_user_link(jjaek.target_user)
    end

    options
  end

  def profile_context_label?(jjaek)
    jjaek.target_user.present? && jjaek.target_user != jjaek.user
  end

  def jjaek_context_user_link(user)
    link_to(user.name, user_path(user), class: "font-semibold text-stone-900 hover:text-stone-700")
  end

  def jjaek_context_book_link(book)
    link_to(book.title, book_path(book), class: "font-semibold text-stone-900 hover:text-stone-700")
  end
end
