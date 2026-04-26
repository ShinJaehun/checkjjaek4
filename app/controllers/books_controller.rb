class BooksController < ApplicationController
  before_action :set_book, only: :show

  def lookup
    book = Book.find_or_initialize_from_search(lookup_book_params)
    authorize book, :show?
    book.save! if book.new_record? || book.changed?

    redirect_to book_path(book)
  end

  def show
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book)
    prepare_book_write_context if @bookshelf_entry.present?
    @jjaeks = visible_book_jjaeks
  end

  private

  def prepare_book_write_context
    authorize @bookshelf_entry
    @quoted_jjaek = find_quoted_jjaek
    @jjaek = Jjaek.new(user: current_user, book: @book, quoted_jjaek: @quoted_jjaek)
    authorize @jjaek
    @sticker_definitions = StickerDefinition.alphabetical
  end

  def find_quoted_jjaek
    return unless params[:quote_id].present?

    policy_scope(@book.jjaeks).find(params[:quote_id])
  end

  def visible_book_jjaeks
    policy_scope(@book.jjaeks.includes(:user, :book, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book ])).recent
  end

  def set_book
    @book = Book.find(params[:id])
    authorize @book, :show?
  end

  def lookup_book_params
    params.permit(:title, :authors_text, :publisher, :thumbnail, :isbn, :description, :external_url)
  end
end
