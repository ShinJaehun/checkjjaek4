class BookshelvesController < ApplicationController
  before_action :set_bookshelf, only: %i[update destroy move_up move_down]

  def create
    @bookshelf = current_user.bookshelves.build(bookshelf_params)
    @bookshelf.is_default = false
    authorize @bookshelf

    if @bookshelf.save
      redirect_to bookshelf_redirect_path(@bookshelf.id),
                  notice: t("bookshelves.notices.created", bookshelf_name: @bookshelf.name)
    else
      @bookshelf_management_modal_mode = "create"
      prepare_library_after_create_failure
      render "users/libraries/show", status: :unprocessable_content
    end
  end

  def update
    authorize @bookshelf

    if @bookshelf.update(bookshelf_params)
      redirect_to bookshelf_redirect_path(@bookshelf.id),
                  notice: t("bookshelves.notices.updated", bookshelf_name: @bookshelf.name)
    else
      @bookshelf_management_modal_mode = "edit"
      prepare_library_after_failure(selected_bookshelf_id: @bookshelf.id, managed_bookshelf: @bookshelf)
      render "users/libraries/show", status: :unprocessable_content
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
    @bookshelf = Bookshelf.find(params[:id])
  end

  def bookshelf_params
    params.fetch(:bookshelf, {}).permit(:name, :visibility, :color_key)
  end

  def prepare_library_after_create_failure
    prepare_library_after_failure(selected_bookshelf_id: params[:bookshelf_id])
  end

  def prepare_library_after_failure(selected_bookshelf_id:, managed_bookshelf: nil)
    @user = current_user
    profile_policy = policy(@user)
    @book_friendship = nil
    @show_bookshelf = profile_policy.show_profile_bookshelf?
    @show_profile_bookshelf_status = profile_policy.show_profile_bookshelf_status?
    @show_profile_bookshelf_move_control = true
    @show_profile_bookshelf_create_form = true
    @bookshelf = current_user.bookshelves.build(visibility: :public, color_key: "stone") unless @bookshelf&.new_record?
    @profile_bookshelf_visibility_options = Bookshelf.visibilities.keys
    @profile_bookshelf_color_options = Bookshelf::COLOR_KEYS
    @profile_bookshelf_sort = library_bookshelf_sort
    @profile_bookshelf_sort_options = BookshelfEntry::PROFILE_SORTS
    @profile_bookshelf_move_targets = current_user.bookshelves.default_first
    @profile_bookshelves = policy_scope(current_user.bookshelves).default_first
    visible_entries = policy_scope(current_user.bookshelf_entries, policy_scope_class: BookshelfEntryPolicy::ProfileScope)
    @profile_bookshelf_entry_counts = visible_entries.group(:bookshelf_id).count
    @selected_bookshelf = selected_library_bookshelf(@profile_bookshelves, selected_bookshelf_id)
    @managed_bookshelf = managed_bookshelf || (@selected_bookshelf if @selected_bookshelf&.is_default? == false)
    @profile_bookshelf_order_controls = bookshelf_order_controls(@profile_bookshelves)
    @bookshelf_entries = @selected_bookshelf ? visible_entries.where(bookshelf: @selected_bookshelf).profile_sorted(@profile_bookshelf_sort) : BookshelfEntry.none
  end

  def library_bookshelf_sort
    BookshelfEntry::PROFILE_SORTS.include?(params[:sort]) ? params[:sort] : "recent"
  end

  def selected_library_bookshelf(accessible_bookshelves, bookshelf_id)
    bookshelves = accessible_bookshelves.to_a
    requested_bookshelf = bookshelves.find { |bookshelf| bookshelf.id.to_s == bookshelf_id.to_s }

    requested_bookshelf || bookshelves.find(&:is_default?) || bookshelves.first
  end

  def fallback_bookshelf_after_destroy
    current_user.bookshelves.default_first.first
  end

  def bookshelf_redirect_path(bookshelf_id)
    user_library_path(current_user, bookshelf_id: bookshelf_id)
  end

  def bookshelf_order_controls(bookshelves)
    regular_bookshelves = bookshelves.reject(&:is_default?)
    regular_bookshelves.each_with_index.to_h do |bookshelf, index|
      [ bookshelf.id, { move_up: index.positive?, move_down: index < regular_bookshelves.size - 1 } ]
    end
  end
end
