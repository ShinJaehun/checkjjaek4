module RecommendationSelection
  extend ActiveSupport::Concern

  included do
    before_action :echo_recommendation_revision
  end

  private

  def echo_recommendation_revision
    revision = request.headers["X-Recommendation-Revision"]
    if revision.is_a?(String) && revision.match?(/\A[0-9a-f-]{36}\z/)
      response.set_header("X-Recommendation-Revision", revision)
    end
  end

  def prepare_editing_recommendation
    @editing_recommendation = Jjaek.find(params[:editing_jjaek_id])
    authorize @editing_recommendation, :update?
    raise ActiveRecord::RecordNotFound unless @editing_recommendation.recommendation?

    @jjaek = @editing_recommendation
    @group = @jjaek.group
    @recommendation_step = "writing"
  end

  def recommendation_context?
    params[:recommendation] == "1"
  end

  def prepare_recommendation_selection(redirect_on_error: true, enforce_limit: true, preserve_on_error: false)
    keys = params.slice(:selected_books)
                 .permit(selected_books: [])
                 .fetch(:selected_books, [])
                 .map(&:to_s)
                 .reject(&:blank?)
                 .uniq
    books = Book.where(id: keys.grep(/\A[1-9]\d*\z/)).index_by { |book| book.id.to_s }
    @selected_books = []
    @selected_book_keys = []
    keys.each do |key|
      book = if key.match?(/\A[1-9]\d*\z/)
        books.fetch(key)
      elsif key.match?(/\Aexternal:[0-9a-f]{32}\z/)
        token = Rails.cache.read(recommendation_cache_key(key))
        attributes = BookSearches::ResultToken.verify(token, user: current_user)
        raise Book::IdentityConflict if attributes.blank?

        Book.find_or_initialize_from_search(attributes)
      else
        raise Book::IdentityConflict
      end
      validate_recommendation_book!(book)
      next if recommendation_book_selected?(book)

      @selected_books << book
      @selected_book_keys << key
    end
    if enforce_limit && !enforce_recommendation_limit
      if redirect_on_error
        flash.keep(:alert)
        redirect_to book_search_path(view_context.recommendation_search_params(query: params[:query], page: params[:page]))
      end
      return false
    end
    true
  rescue Book::IdentityConflict, KeyError, ActiveRecord::RecordNotFound
    unless preserve_on_error
      @selected_books = []
      @selected_book_keys = []
    end
    if redirect_on_error
      flash[:recommendation_selection_reset] = true
      options = { recommendation: 1, group_id: @group&.id, query: params[:query], page: params[:page] }.compact
      if @editing_recommendation
        options.merge!(editing_jjaek_id: @editing_recommendation.id, selected_books: [ "" ],
          return_to: view_context.validated_jjaek_return_path(params[:return_to]))
      end
      options[:search_origin] = view_context.recommendation_origin_path if params[:search_origin].present?
      redirect_to book_search_path(options),
                  alert: t("recommendations.invalid_selection")
    else
      flash.now[:alert] = t("recommendations.invalid_selection")
    end
    false
  end

  def enforce_recommendation_limit
    return true if @selected_books.size <= Jjaek::MAX_RECOMMENDATION_BOOKS

    @selected_books = @selected_books.first(Jjaek::MAX_RECOMMENDATION_BOOKS)
    @selected_book_keys = @selected_book_keys.first(Jjaek::MAX_RECOMMENDATION_BOOKS)
    flash.now[:alert] = t("recommendations.limit_reached", count: Jjaek::MAX_RECOMMENDATION_BOOKS)
    false
  end

  def validate_recommendation_book!(book)
    raise Book::IdentityConflict unless book&.valid?
    if book.new_record? && book.canonical_isbn.blank? && book.external_url.blank?
      raise Book::IdentityConflict
    end
  end

  def recommendation_book_selected?(book)
    identity = recommendation_book_identity(book)
    @selected_books.any? { |selected| recommendation_book_identity(selected) == identity }
  end

  def recommendation_book_identity(book)
    book.id || book.canonical_isbn || book.external_url
  end

  def cache_external_recommendation(token)
    key = "external:#{SecureRandom.hex(16)}"
    stored = Rails.cache.write(recommendation_cache_key(key), token,
                               expires_in: BookSearches::ResultToken::EXPIRES_IN)
    raise Book::IdentityConflict unless stored

    key
  end

  def clear_recommendation_selection
    @selected_book_keys.grep(/\Aexternal:/).each do |key|
      Rails.cache.delete(recommendation_cache_key(key))
    end
  end

  def recommendation_cache_key(key)
    [ "recommendation_selection", current_user.id, key ]
  end
end
