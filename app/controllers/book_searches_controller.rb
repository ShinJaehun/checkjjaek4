class BookSearchesController < ApplicationController
  def show
    authorize :book_search, :show?

    @query = params[:query].to_s.strip
    @page = normalized_page
    @results = []
    @meta = {}
    @has_previous_page = false
    @has_next_page = false
    return if @query.blank?

    result = BookSearches::SearchService.call(query: @query, page: @page)
    @results = mark_shelved_results(result[:results])
    @meta = result[:meta]
    @has_previous_page = @page > 1
    @has_next_page = @meta[:is_end] == false
  rescue BookSearches::KakaoAdapter::Error
    flash.now[:alert] = t("book_search.errors.generic")
  end

  private

  def normalized_page
    page = Integer(params[:page], exception: false)
    page&.positive? ? page : 1
  end

  def mark_shelved_results(results)
    isbns = results.filter_map { |book| normalized_presence(book[:isbn]) }
    external_urls = results.filter_map { |book| normalized_presence(book[:url]) }
    return results if isbns.empty? && external_urls.empty?

    books = shelved_books_matching(isbns:, external_urls:)
    books_by_isbn = books.select { |book| book.isbn.present? }.index_by(&:isbn)
    books_by_external_url = books.select { |book| book.external_url.present? }.index_by(&:external_url)

    results.map do |book|
      shelved_book = books_by_isbn[normalized_presence(book[:isbn])] ||
                     books_by_external_url[normalized_presence(book[:url])]

      book.merge(shelved_book_id: shelved_book&.id)
    end
  end

  def shelved_books_matching(isbns:, external_urls:)
    scope = Book.joins(:bookshelf_entries)
      .where(bookshelf_entries: { user_id: current_user.id })

    if isbns.any? && external_urls.any?
      scope.where(isbn: isbns).or(scope.where(external_url: external_urls)).distinct
    elsif isbns.any?
      scope.where(isbn: isbns).distinct
    else
      scope.where(external_url: external_urls).distinct
    end
  end

  def normalized_presence(value)
    value.to_s.strip.presence
  end
end
