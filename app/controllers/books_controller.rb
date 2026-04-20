class BooksController < ApplicationController
  before_action :set_book

  def lookup
    book = Book.find_or_initialize_from_search(lookup_book_params)
    authorize book, :show?
    book.save! if book.new_record? || book.changed?

    redirect_to book_path(book)
  end

  def show
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book) || current_user.bookshelf_entries.build(book: @book)
    authorize @bookshelf_entry
    @quoted_jjaek = params[:quote_id].present? ? policy_scope(@book.jjaeks).find(params[:quote_id]) : nil
    @jjaek = current_user.jjaeks.build(book: @book, quoted_jjaek: @quoted_jjaek)
    authorize @jjaek
    @sticker_definitions = StickerDefinition.alphabetical
    @jjaeks = policy_scope(@book.jjaeks.includes(:user, :likes, :comments, :quoted_jjaek)).recent
  end

  private

  def set_book
    @book = Book.find(params[:id])
    authorize @book, :show?
  end

  def lookup_book_params
    params.permit(:title, :authors_text, :publisher, :thumbnail, :isbn, :description, :external_url)
  end
end
