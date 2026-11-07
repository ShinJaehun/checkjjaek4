module BookSelection
  extend ActiveSupport::Concern

  included do
    before_action :echo_selection_revision
  end

  private

  def echo_selection_revision
    revision = request.headers["X-Book-Selection-Revision"]
    response.set_header("X-Book-Selection-Revision", revision) if revision.is_a?(String) && revision.match?(/\A[0-9a-f-]{36}\z/)
  end

  def prepare_book_selection_context
    %i[editing_jjaek_id group_id target_user_id].each do |key|
      next if params[key].blank?
      raise Pundit::NotAuthorizedError unless params[key].is_a?(String) && params[key].match?(/\A[1-9]\d*\z/)
    end
    if params[:editing_jjaek_id].present?
      @jjaek = Jjaek.find(params[:editing_jjaek_id])
      authorize @jjaek, :update?
      raise Pundit::NotAuthorizedError if @jjaek.requote?
      @group = @jjaek.group
    else
      @group = policy_scope(Group).find(params[:group_id]) if params[:group_id].present?
      target = User.find(params[:target_user_id]) if params[:target_user_id].present?
      raise Pundit::NotAuthorizedError if @group && target
      @jjaek = Jjaek.new(user: current_user, group: @group, target_user: target)
      authorize @jjaek, :create?
    end
    @selection_origin = if @jjaek.persisted?
      edit_jjaek_path(@jjaek, return_to: view_context.validated_jjaek_return_path(params[:return_to]))
    else
      origin = view_context.validated_jjaek_return_path(params[:search_origin])
      origin = nil if origin && URI.parse(origin).path == book_search_path
      origin || (@group ? group_path(@group) : (@jjaek.target_user ? user_path(@jjaek.target_user) : root_path))
    end
    response.headers["Cache-Control"] = "no-store"
  end

  def prepare_book_selection(preserve_on_error: false)
    @selected_books = []
    @selected_book_keys = []
    raw_keys = params.fetch(:selected_books, [])
    unless raw_keys.is_a?(Array) && raw_keys.all? { |key| key.is_a?(String) || key.is_a?(Integer) }
      raise Book::IdentityConflict
    end

    keys = params.slice(:selected_books)
                 .permit(selected_books: [])
                 .fetch(:selected_books, [])
                 .map(&:to_s)
                 .reject(&:empty?)
    raise Book::IdentityConflict if keys.uniq.size != keys.size
    books = Book.where(id: keys.grep(/\A[1-9]\d*\z/)).index_by { |book| book.id.to_s }
    keys.each do |key|
      book = if key.match?(/\A[1-9]\d*\z/)
        books.fetch(key)
      elsif key.match?(/\Aexternal:[0-9a-f]{32}\z/)
        token = Rails.cache.read(book_selection_cache_key(key))
        attributes = BookSearches::ResultToken.verify(token, user: current_user)
        raise Book::IdentityConflict if attributes.blank?

        Book.find_or_initialize_from_search(attributes)
      else
        raise Book::IdentityConflict
      end
      validate_selected_book!(book)
      raise Book::IdentityConflict if selected_book?(book)

      @selected_books << book
      @selected_book_keys << key
    end
    true
  rescue Book::IdentityConflict, KeyError, ActiveRecord::RecordNotFound
    unless preserve_on_error
      @selected_books = []
      @selected_book_keys = []
    end
    flash.now[:alert] = t("jjaek_books.invalid_selection")
    false
  end

  def validate_selected_book!(book)
    raise Book::IdentityConflict unless book&.valid?
    if book.new_record? && book.canonical_isbn.blank? && book.external_url.blank?
      raise Book::IdentityConflict
    end
  end

  def selected_book?(book)
    identity = selected_book_identity(book)
    @selected_books.any? { |selected| selected_book_identity(selected) == identity }
  end

  def selected_book_identity(book)
    book.id || book.canonical_isbn || book.external_url
  end

  def cache_external_book(token)
    key = "external:#{SecureRandom.hex(16)}"
    stored = Rails.cache.write(book_selection_cache_key(key), token,
                               expires_in: BookSearches::ResultToken::EXPIRES_IN)
    raise Book::IdentityConflict unless stored

    key
  end

  def clear_book_selection
    @selected_book_keys.grep(/\Aexternal:/).each do |key|
      Rails.cache.delete(book_selection_cache_key(key))
    end
  end

  def book_selection_cache_key(key)
    [ "book_selection", current_user.id, key ]
  end
end
