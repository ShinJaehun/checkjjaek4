module BookSearchesHelper
  def book_search_result_dom_id(book)
    return "book_search_result_stored_#{book[:existing_book_id]}" if book[:existing_book_id].present? && book[:search_result_token].blank?

    identifier = book[:isbn].presence || book[:external_url].presence || book[:url].presence || book[:title].to_s

    "book_search_result_#{Digest::SHA256.hexdigest(identifier)[0, 12]}"
  end

  def book_search_result_path(book, group_id: nil)
    existing_id = book[:existing_book_id] || book[:shelved_book_id]
    return book_path(existing_id, group_id:) if existing_id.present?

    lookup_books_path(search_result_token: book[:search_result_token], group_id:)
  end

  def book_search_bookshelf_select_id(book)
    "bookshelf_entry_bookshelf_id_#{book.object_id}"
  end
end
