module BookSearchesHelper
  def book_search_result_dom_id(book)
    identifier = book[:isbn].presence || book[:external_url].presence || book[:url].presence || book[:title].to_s

    "book_search_result_#{Digest::SHA256.hexdigest(identifier)[0, 12]}"
  end

  def book_search_result_path(book)
    return book_path(book[:shelved_book_id]) if book[:shelved_book_id].present?

    lookup_books_path(
      title: book[:title],
      authors_text: book[:authors_text],
      publisher: book[:publisher],
      thumbnail: book[:thumbnail],
      isbn: book[:isbn],
      description: book[:contents_excerpt],
      external_url: book[:url]
    )
  end

  def book_search_bookshelf_select_id(book)
    "bookshelf_entry_bookshelf_id_#{book.object_id}"
  end
end
