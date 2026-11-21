class BookNotesController < ApplicationController
  include BookShowContext

  before_action :set_user_book
  before_action :no_store

  def show
    set_book_note
    authorize @book_note
    prepare_note_view
    render :show, formats: :html
  end

  def create
    @new_book_note = @user_book.book_notes.build
    saved = @user_book.with_lock do
      authorize @new_book_note
      @new_book_note.update(book_note_params)
    end

    if saved
      redirect_to book_path(@book, return_to: safe_return_path, tab: "reading", anchor: "book-notes"), status: :see_other
    else
      @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book)
      @jjaek = Jjaek.new(user: current_user)
      @selected_books = [ @book ]
      @selected_book_keys = [ @book.id.to_s ]
      @sticker_definitions = StickerDefinition.alphabetical
      prepare_book_show_read_context
      render "books/show", formats: :html, status: :unprocessable_content
    end
  end

  def update
    saved = @user_book.with_lock do
      set_book_note
      authorize @book_note
      @book_note.update(book_note_params)
    end

    if saved
      redirect_to book_book_note_path(@book, @book_note, return_to: safe_return_path), status: :see_other
    else
      @book_note_draft = @book_note
      set_book_note
      prepare_note_view
      render :show, formats: :html, status: :unprocessable_content
    end
  end

  def destroy
    @user_book.with_lock do
      set_book_note
      authorize @book_note
      @book_note.destroy!
    end

    redirect_to note_back_path, status: :see_other
  end

  private

  def set_user_book
    @user_book = current_user.user_books.find_by!(book_id: params[:book_id])
    @book = @user_book.book
  end

  def set_book_note
    @book_note = current_user.user_books
      .find_by!(book_id: params[:book_id])
      .book_notes.find(params[:id])
  end

  def prepare_note_view
    @can_change_book_note = policy(@book_note).update?
    @note_back_path = note_back_path
    @note_path = book_book_note_path(@book, @book_note, return_to: safe_return_path)
  end

  def note_back_path
    return book_path(@book, tab: "reading", anchor: "book-notes") unless safe_return_path

    uri = URI.parse(safe_return_path)
    options = Rack::Utils.parse_query(uri.query)
    case uri.path
    when user_library_path(current_user)
      user_library_path(current_user, options.merge("library_tab" => "notes", anchor: "book-notes"))
    when book_path(@book)
      book_path(@book, options.merge("tab" => "reading", anchor: "book-notes"))
    else
      safe_return_path
    end
  end

  def safe_return_path
    @safe_return_path ||= view_context.validated_jjaek_return_path(params[:return_to])
  end

  def book_note_params
    params.expect(book_note: %i[title body])
  end
end
