class BookshelfEntriesController < ApplicationController
  before_action :set_bookshelf_entry, only: %i[edit update destroy]

  def index
    authorize BookshelfEntry
    @bookshelf_entries = policy_scope(BookshelfEntry).recent_first
  end

  def new
    @book = Book.find(params[:book_id])
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book) || new_bookshelf_entry_for(@book)
    authorize @bookshelf_entry
    @sticker_definitions = StickerDefinition.alphabetical
  end

  def edit
    authorize @bookshelf_entry
    @book = @bookshelf_entry.book
    @sticker_definitions = StickerDefinition.alphabetical
  end

  def create
    @book = Book.find_or_initialize_from_search(book_attributes)
    @book.save! if @book.new_record? || @book.changed?

    @bookshelf_entry = current_user.bookshelf_entries.find_or_initialize_by(book: @book)
    authorize @bookshelf_entry

    @bookshelf_entry.assign_attributes(bookshelf_entry_params.except(:sticker_definition_ids))
    assign_stickers(@bookshelf_entry)

    if @bookshelf_entry.save
      redirect_to book_path(@book), notice: t("bookshelf_entries.notices.created")
    else
      @sticker_definitions = StickerDefinition.alphabetical
      redirect_back fallback_location: book_search_path, alert: @bookshelf_entry.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @bookshelf_entry
    @bookshelf_entry.assign_attributes(bookshelf_entry_params.except(:sticker_definition_ids))
    assign_stickers(@bookshelf_entry)

    if @bookshelf_entry.save
      redirect_to book_path(@bookshelf_entry.book), notice: t("bookshelf_entries.notices.updated")
    else
      prepare_book_show_failure
      render "books/show", status: :unprocessable_content
    end
  end

  def destroy
    authorize @bookshelf_entry
    @bookshelf_entry.destroy!

    redirect_to bookshelf_entries_path, notice: t("bookshelf_entries.notices.destroyed"), status: :see_other
  end

  private

  def set_bookshelf_entry
    @bookshelf_entry = current_user.bookshelf_entries.find(params[:id])
  end

  def bookshelf_entry_params
    params.require(:bookshelf_entry).permit(:status, sticker_definition_ids: [])
  end

  def book_attributes
    params.fetch(:book, {}).permit(:title, :authors_text, :publisher, :thumbnail, :isbn, :description, :external_url)
  end

  def new_bookshelf_entry_for(book)
    BookshelfEntry.new(user: current_user, book:)
  end

  def prepare_book_show_failure
    @book = @bookshelf_entry.book
    @sticker_definitions = StickerDefinition.alphabetical
    @quoted_jjaek = nil
    @jjaek = Jjaek.new(user: current_user, book: @book)
    authorize @jjaek
    @jjaeks = policy_scope(@book.jjaeks.includes(:user, :likes, :comments, :quoted_jjaek)).recent
  end

  def assign_stickers(entry)
    entry.sticker_definition_ids = Array(bookshelf_entry_params[:sticker_definition_ids]).reject(&:blank?)
  end
end
