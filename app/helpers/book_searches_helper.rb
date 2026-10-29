module BookSearchesHelper
  def book_search_result_dom_id(book)
    return "book_search_result_stored_#{book[:existing_book_id]}" if book[:existing_book_id].present? && book[:search_result_token].blank?

    identifier = book[:isbn].presence || book[:external_url].presence || book[:url].presence || book[:title].to_s

    "book_search_result_#{Digest::SHA256.hexdigest(identifier)[0, 12]}"
  end

  def book_search_entry_path(group_id: nil)
    book_search_path(group_id: group_id, search_origin: book_search_entry_origin_path)
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

  def book_search_bookshelf_select_id(book)
    "bookshelf_entry_bookshelf_id_#{book.object_id}"
  end
end
