module BookSearchesHelper
  def book_search_page_path(page)
    return book_search_path(recommendation_search_params(page: page)) if @recommendation_context
    book_search_path(query: @query, page: page, group_id: @group&.id, search_origin: book_search_origin_path)
  end

  def recommendation_search_params(page: @page)
    { attachment: 1, query: @query, page: page, selected_books: ["", *@selected_book_keys],
      group_id: @jjaek.group_id, target_user_id: @jjaek.target_user_id,
      editing_jjaek_id: @jjaek.id, search_origin: @selection_origin,
      return_to: validated_jjaek_return_path(params[:return_to]) }.compact
  end

  def recommendation_result_isbn(book)
    Book.canonical_isbn_for(book[:isbn])
  rescue Book::IdentityConflict
    nil
  end

  def recommendation_result_selected?(result)
    @selected_books.any? do |book|
      (result[:existing_book_id].present? && book.id == result[:existing_book_id]) ||
        (book.canonical_isbn.present? && book.canonical_isbn == recommendation_result_isbn(result)) ||
        (book.external_url.present? && book.external_url == result[:url])
    end
  end

  def book_search_result_dom_id(book)
    return "book_search_result_stored_#{book[:existing_book_id]}" if book[:existing_book_id].present? && book[:search_result_token].blank?

    identifier = book[:isbn].presence || book[:external_url].presence || book[:url].presence || book[:title].to_s

    "book_search_result_#{Digest::SHA256.hexdigest(identifier)[0, 12]}"
  end

  def book_search_entry_origin_path
    controller_path == "book_searches" ? book_search_origin_path : validated_jjaek_return_path(request.fullpath)
  end

  def book_search_origin_path
    validated_jjaek_return_path(params[:search_origin], include_search_origin: false)
  end

  def book_search_result_path(book, group_id: nil, return_path:)
    existing_id = book[:existing_book_id] || book[:shelved_book_id]
    options = { group_id: group_id, return_to: return_path }
    return book_path(existing_id, options) if existing_id.present?

    lookup_books_path(options.merge(search_result_token: book[:search_result_token]))
  end

  def book_search_return_path
    validated_jjaek_return_path(book_search_path(query: @query, page: @page, group_id: @group&.id,
                                              search_origin: book_search_origin_path))
  end
end
