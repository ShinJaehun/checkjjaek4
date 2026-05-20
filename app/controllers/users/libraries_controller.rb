class Users::LibrariesController < ApplicationController
  def show
    @user = User.find(params[:user_id])
    authorize @user, :show?
    return redirect_to user_path(@user) unless policy(@user).show_library?

    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    prepare_library_bookshelf(policy(@user))
  end

  def transfer
    @user = User.find(params[:user_id])
    authorize @user, :show?
    return redirect_to user_path(@user) unless policy(@user).show_library?
    return redirect_to user_library_path(@user) unless current_user == @user

    prepare_bookshelf_transfer
  end

  private

  def prepare_library_bookshelf(profile_policy)
    @show_bookshelf = profile_policy.show_profile_bookshelf?
    @show_profile_bookshelf_status = profile_policy.show_profile_bookshelf_status?
    @show_profile_bookshelf_move_control = current_user == @user
    @show_profile_bookshelf_create_form = current_user == @user
    @bookshelf = current_user.bookshelves.build(visibility: :public, color_key: "stone") if @show_profile_bookshelf_create_form
    @profile_bookshelf_visibility_options = Bookshelf.visibilities.keys
    @profile_bookshelf_color_options = Bookshelf::COLOR_KEYS
    @profile_bookshelf_sort = library_bookshelf_sort
    @profile_bookshelf_sort_options = BookshelfEntry::PROFILE_SORTS
    @profile_bookshelf_view = "detail"

    return unless @show_bookshelf

    @profile_bookshelves = policy_scope(@user.bookshelves).default_first
    visible_entries = policy_scope(@user.bookshelf_entries, policy_scope_class: BookshelfEntryPolicy::ProfileScope)
    @profile_bookshelf_entry_counts = visible_entries.group(:bookshelf_id).count
    @selected_bookshelf = selected_library_bookshelf(@profile_bookshelves)
    @managed_bookshelf = @selected_bookshelf if @show_profile_bookshelf_create_form && @selected_bookshelf&.is_default? == false
    @profile_bookshelf_order_controls = @show_profile_bookshelf_create_form ? bookshelf_order_controls(@profile_bookshelves) : {}
    @bookshelf_entries =
      if @selected_bookshelf
        visible_entries.where(bookshelf: @selected_bookshelf).profile_sorted(@profile_bookshelf_sort)
      else
        BookshelfEntry.none
      end
  end

  def prepare_bookshelf_transfer
    @profile_bookshelves = current_user.bookshelves.default_first.to_a
    return redirect_to user_library_path(@user), alert: t("users.library.transfer.not_enough_bookshelves") if @profile_bookshelves.size < 2

    @profile_bookshelf_entry_counts = current_user.bookshelf_entries.group(:bookshelf_id).count
    @source_bookshelf, @target_bookshelf = transfer_bookshelf_pair(@profile_bookshelves)
    @source_bookshelf_entries = current_user.bookshelf_entries.where(bookshelf: @source_bookshelf).profile_sorted("manual")
    @target_bookshelf_entries = current_user.bookshelf_entries.where(bookshelf: @target_bookshelf).profile_sorted("manual")
  end

  def library_bookshelf_sort
    return params[:sort] if BookshelfEntry::PROFILE_SORTS.include?(params[:sort])

    current_user == @user ? "manual" : "recent"
  end

  def selected_library_bookshelf(accessible_bookshelves)
    bookshelves = accessible_bookshelves.to_a
    requested_bookshelf = bookshelves.find { |bookshelf| bookshelf.id.to_s == params[:bookshelf_id].to_s }

    requested_bookshelf || bookshelves.find(&:is_default?) || bookshelves.first
  end

  def bookshelf_order_controls(bookshelves)
    regular_bookshelves = bookshelves.reject(&:is_default?)
    regular_bookshelves.each_with_index.to_h do |bookshelf, index|
      [ bookshelf.id, { move_up: index.positive?, move_down: index < regular_bookshelves.size - 1 } ]
    end
  end

  def transfer_bookshelf_pair(bookshelves)
    source_bookshelf = transfer_source_bookshelf(bookshelves)
    target_bookshelf = transfer_target_bookshelf(bookshelves)

    if source_bookshelf.id == target_bookshelf.id
      if params[:changed] == "target"
        source_bookshelf = next_bookshelf_after(bookshelves, target_bookshelf)
      else
        target_bookshelf = next_bookshelf_after(bookshelves, source_bookshelf)
      end
    end

    [ source_bookshelf, target_bookshelf ]
  end

  def transfer_source_bookshelf(bookshelves)
    requested_id = params[:source_bookshelf_id].presence || params[:bookshelf_id]
    requested_bookshelf = bookshelves.find { |bookshelf| bookshelf.id.to_s == requested_id.to_s }

    requested_bookshelf || bookshelves.find(&:is_default?) || bookshelves.first
  end

  def transfer_target_bookshelf(bookshelves)
    requested_bookshelf = bookshelves.find { |bookshelf| bookshelf.id.to_s == params[:target_bookshelf_id].to_s }

    requested_bookshelf || next_bookshelf_after(bookshelves, transfer_source_bookshelf(bookshelves))
  end

  def next_bookshelf_after(bookshelves, bookshelf)
    index = bookshelves.index { |candidate| candidate.id == bookshelf.id }

    bookshelves[(index + 1) % bookshelves.size]
  end

  def transfer_path_for(source_bookshelf:, target_bookshelf:, changed:)
    transfer_user_library_path(
      @user,
      source_bookshelf_id: source_bookshelf.id,
      target_bookshelf_id: target_bookshelf.id,
      changed:
    )
  end
  helper_method :transfer_path_for
end
