module BookshelfEntriesHelper
  def bookshelf_entry_book_hidden_fields(book)
    safe_join(
      [
        hidden_field_tag("book[title]", book.title),
        hidden_field_tag("book[authors_text]", book.authors_text),
        hidden_field_tag("book[publisher]", book.publisher),
        hidden_field_tag("book[thumbnail]", book.thumbnail),
        hidden_field_tag("book[isbn]", book.isbn),
        hidden_field_tag("book[description]", book.description),
        hidden_field_tag("book[external_url]", book.external_url)
      ]
    )
  end
end
