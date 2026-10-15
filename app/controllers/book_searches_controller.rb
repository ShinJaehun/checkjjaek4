class BookSearchesController < ApplicationController
  def show
    authorize :book_search, :show?
    @group = find_group_context
    authorize @group, :create_jjaek? if @group.present?

    @query = params[:query].to_s.strip
    @page = normalized_page
    @results = []
    @meta = {}
    @has_previous_page = false
    @has_next_page = false
    @bookshelves = current_user.bookshelves.default_first
    @local_results = []
    unless @query.blank?
      @bookshelves = @bookshelves.to_a
      prepare_local_results
      prepare_external_results
    end
    render partial: "book_searches/modal_results" if params[:modal] == "1"
  end

  private

  def prepare_local_results
    query = "%#{Book.sanitize_sql_like(@query)}%"
    books = Book.where("title ILIKE :query OR authors_text ILIKE :query OR publisher ILIKE :query", query: query)
      .order(:title, :id).offset((@page - 1) * BookSearches::SearchService::DEFAULT_SIZE)
      .limit(BookSearches::SearchService::DEFAULT_SIZE + 1).to_a
    @has_next_page = books.size > BookSearches::SearchService::DEFAULT_SIZE
    books = books.first(BookSearches::SearchService::DEFAULT_SIZE)
    shelved_ids = current_user.bookshelf_entries.where(book_id: books.map(&:id)).pluck(:book_id)
    @local_results = books.map do |book|
      { title: book.title, authors_text: book.authors_text, publisher: book.publisher,
        thumbnail: book.thumbnail, isbn: book.isbn, contents_excerpt: book.description,
        url: book.external_url, existing_book_id: book.id,
        shelved_book_id: (book.id if shelved_ids.include?(book.id)) }
    end
    @has_previous_page = @page > 1
  end

  def prepare_external_results
    result = BookSearches::SearchService.call(query: @query, page: @page)
    local_ids = @local_results.map { |book| book[:existing_book_id] }
    results = mark_shelved_results(result[:results]).reject do |book|
      book[:existing_book_id].present? && local_ids.include?(book[:existing_book_id])
    end
    @results = results.map do |book|
      book.merge(search_result_token: BookSearches::ResultToken.issue(book, user: current_user))
    end
    @meta = result[:meta]
    @has_next_page ||= @meta[:is_end] == false
  rescue BookSearches::KakaoAdapter::Error
    @external_search_failed = true
    flash.now[:alert] = t("book_search.errors.generic") unless params[:modal] == "1"
  end

  def normalized_page
    page = Integer(params[:page], exception: false)
    page&.positive? ? page : 1
  end

  def find_group_context
    return if params[:group_id].blank?

    policy_scope(Group).find(params[:group_id])
  end

  def mark_shelved_results(results)
    identities = results.map do |result|
      [ Book.canonical_isbn_for(result[:isbn]), valid_external_url(result[:url]) ]
    rescue Book::IdentityConflict
      [ :ambiguous, nil ]
    end
    isbns = identities.filter_map { |isbn, _| isbn if isbn != :ambiguous }
    external_urls = identities.filter_map(&:last)
    books = shelved_books_matching(isbns:, external_urls:)
    shelved_book_ids = current_user.bookshelf_entries.where(book_id: books.map(&:id)).pluck(:book_id)
    books_by_isbn = books.select { |book| book.canonical_isbn.present? }.index_by(&:canonical_isbn)
    books_by_external_url = books.select { |book| book.external_url.present? }.index_by(&:external_url)

    results.zip(identities).map do |book, (isbn, url)|
      isbn_book = books_by_isbn[isbn] unless isbn == :ambiguous
      url_book = books_by_external_url[url]
      shelved_book =
        if isbn == :ambiguous || (isbn && url_book && url_book != isbn_book)
          nil
        elsif isbn
          isbn_book
        else
          url_book
        end

      book.merge(existing_book_id: shelved_book&.id, shelved_book_id: shelved_book_ids.include?(shelved_book&.id) ? shelved_book.id : nil)
    end
  end

  def shelved_books_matching(isbns:, external_urls:)
    scope = Book.all

    if isbns.any? && external_urls.any?
      scope.where(canonical_isbn: isbns).or(scope.where(external_url: external_urls)).distinct
    elsif isbns.any?
      scope.where(canonical_isbn: isbns).distinct
    elsif external_urls.any?
      scope.where(external_url: external_urls).distinct
    else
      scope.none
    end
  end

  def valid_external_url(value)
    value.to_s.strip if Book.valid_http_url?(value)
  end
end
