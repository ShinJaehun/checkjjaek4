class BookshelvesController < ApplicationController
  include LibraryBookshelfContext

  before_action :set_bookshelf, only: %i[update destroy move_up move_down]

  def create
    saved = current_user.with_lock do
      raise Pundit::NotAuthorizedError unless current_user.active_account? && !current_user.suspended?

      @bookshelf = current_user.bookshelves.build(bookshelf_params)
      @bookshelf.is_default = false
      authorize @bookshelf
      @bookshelf.save
    end

    if saved
      redirect_to bookshelf_redirect_path(@bookshelf.id),
                  notice: t("bookshelves.notices.created", bookshelf_name: @bookshelf.name)
    else
      @bookshelf_management_modal_mode = "create"
      render_library_after_failure(new_bookshelf: @bookshelf)
    end
  end

  def update
    authorize @bookshelf

    if @bookshelf.update(bookshelf_params)
      redirect_to bookshelf_redirect_path(@bookshelf.id),
                  notice: t("bookshelves.notices.updated", bookshelf_name: @bookshelf.name)
    else
      @bookshelf_management_modal_mode = "edit"
      render_library_after_failure(selected_bookshelf_id: @bookshelf.id, managed_bookshelf: @bookshelf)
    end
  end

  def destroy
    if @bookshelf.is_default? && @bookshelf.user_id == current_user.id
      return redirect_to bookshelf_redirect_path(@bookshelf.id),
                         alert: t("bookshelves.alerts.default_destroy_denied"),
                         status: :see_other
    end

    authorize @bookshelf

    if @bookshelf.bookshelf_entries.exists?
      return redirect_to bookshelf_redirect_path(@bookshelf.id),
                         alert: t("bookshelves.alerts.not_empty"),
                         status: :see_other
    end

    if @bookshelf.destroy
      redirect_to bookshelf_redirect_path(fallback_bookshelf_after_destroy&.id),
                  notice: t("bookshelves.notices.destroyed", bookshelf_name: @bookshelf.name),
                  status: :see_other
    else
      redirect_to bookshelf_redirect_path(@bookshelf.id),
                  alert: @bookshelf.errors.full_messages.to_sentence.presence || t("bookshelves.alerts.destroy_failed"),
                  status: :see_other
    end
  end

  def move_up
    authorize @bookshelf
    @bookshelf.move_up!

    redirect_to bookshelf_redirect_path(@bookshelf.id),
                notice: t("bookshelves.notices.moved", bookshelf_name: @bookshelf.name)
  end

  def move_down
    authorize @bookshelf
    @bookshelf.move_down!

    redirect_to bookshelf_redirect_path(@bookshelf.id),
                notice: t("bookshelves.notices.moved", bookshelf_name: @bookshelf.name)
  end

  private

  def set_bookshelf
    @bookshelf = Bookshelf.find_by(id: params[:id])
    return if @bookshelf

    redirect_to user_library_path(current_user), alert: t("bookshelves.alerts.stale_action"), status: :see_other
  end

  def bookshelf_params
    params.fetch(:bookshelf, {}).permit(:name, :visibility, :color_key)
  end

  def render_library_after_failure(**options)
    @user = current_user
    prepare_library_bookshelf(**options)
    render "users/libraries/show", status: :unprocessable_content
  end

  def fallback_bookshelf_after_destroy
    current_user.bookshelves.default_first.first
  end

  def bookshelf_redirect_path(bookshelf_id)
    user_library_path(current_user, bookshelf_id: bookshelf_id)
  end
end
