module BooksHelper
  def book_metadata_rows(book)
    {
      authors: book.authors_text,
      translators: book.translators_text,
      publisher: book.publisher,
      published_on: (l(book.published_on, format: :book_publication) if book.published_on.present?),
      isbn: book.isbn
    }.select { |_, value| value.present? }
  end
end
