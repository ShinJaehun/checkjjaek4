module JjaeksHelper
  def jjaek_context_label(jjaek)
    if jjaek.quoted_jjaek.present?
      safe_join(
        [
          jjaek_context_user_link(jjaek.user),
          jjaek_context_text("님이 "),
          jjaek_context_user_link(jjaek.quoted_jjaek.user),
          jjaek_context_text("님의 짹을 다시짹")
        ]
      )
    elsif jjaek.book.present?
      safe_join(
        [
          jjaek_context_user_link(jjaek.user),
          jjaek_context_text("님이 "),
          jjaek_context_book_link(jjaek.book),
          jjaek_context_text("에 남긴 책짹")
        ]
      )
    elsif jjaek.target_user.present?
      safe_join(
        [
          jjaek_context_user_link(jjaek.user),
          jjaek_context_text("님이 "),
          jjaek_context_user_link(jjaek.target_user),
          jjaek_context_text("님에게 남긴 짹")
        ]
      )
    else
      safe_join(
        [
          jjaek_context_user_link(jjaek.user),
          jjaek_context_text("님의 짹")
        ]
      )
    end
  end

  private

  def jjaek_context_user_link(user)
    link_to(user.name, user_path(user), class: "font-semibold text-stone-900 hover:text-stone-700")
  end

  def jjaek_context_text(text)
    content_tag(:span, text, class: "font-normal text-stone-600")
  end

  def jjaek_context_book_link(book)
    link_to(book.title, book_path(book), class: "font-semibold text-stone-900 hover:text-stone-700")
  end
end
