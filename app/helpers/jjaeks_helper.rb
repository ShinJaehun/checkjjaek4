module JjaeksHelper
  def jjaek_context_label(jjaek)
    if jjaek.quoted_jjaek.present?
      t(
        "jjaeks.contexts.requote_html",
        author_name: jjaek_context_user_link(jjaek.user),
        quoted_user_name: jjaek_context_user_link(jjaek.quoted_jjaek.user)
      )
    elsif jjaek.book.present?
      t(
        "jjaeks.contexts.book_html",
        author_name: jjaek_context_user_link(jjaek.user),
        book_title: jjaek_context_book_link(jjaek.book)
      )
    elsif jjaek.target_user.present?
      t(
        "jjaeks.contexts.profile_html",
        author_name: jjaek_context_user_link(jjaek.user),
        target_user_name: jjaek_context_user_link(jjaek.target_user)
      )
    else
      t(
        "jjaeks.contexts.general_html",
        author_name: jjaek_context_user_link(jjaek.user)
      )
    end
  end

  private

  def jjaek_context_user_link(user)
    link_to(user.name, user_path(user), class: "font-semibold text-stone-900 hover:text-stone-700")
  end

  def jjaek_context_book_link(book)
    link_to(book.title, book_path(book), class: "font-semibold text-stone-900 hover:text-stone-700")
  end
end
