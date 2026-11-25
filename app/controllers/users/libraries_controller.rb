class Users::LibrariesController < ApplicationController
  include LibraryBookshelfContext

  def show
    @user = User.find_by_public_param!(params[:user_id])
    authorize @user, :show?
    return redirect_to user_path(@user) unless policy(@user).show_library?

    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    show_notes = params[:library_tab] == "notes" || (params[:library_tab].blank? && params[:notes_page].present?)
    prepare_library_bookshelf(show_notes:)
  end

  def transfer
    @user = User.find_by_public_param!(params[:user_id])
    authorize @user, :show?
    return redirect_to user_path(@user) unless policy(@user).show_library?
    return redirect_to user_library_path(@user) unless current_user == @user

    prepare_bookshelf_transfer
  end

  private

  def prepare_bookshelf_transfer
    @organizing_bookshelf = params[:mode] == "organize"
    @profile_bookshelves = current_user.bookshelves.default_first.to_a
    required_shelves = @organizing_bookshelf ? 1 : 2
    if @profile_bookshelves.size < required_shelves
      return redirect_to user_library_path(@user), alert: t("users.library.transfer.not_enough_bookshelves")
    end

    @profile_bookshelf_entry_counts = current_user.bookshelf_entries.group(:bookshelf_id).count
    if @organizing_bookshelf
      @source_bookshelf = transfer_source_bookshelf(@profile_bookshelves)
    else
      @source_bookshelf, @target_bookshelf = transfer_bookshelf_pair(@profile_bookshelves)
      @target_bookshelf_entries = current_user.bookshelf_entries.where(bookshelf: @target_bookshelf).profile_sorted("manual")
    end
    @source_bookshelf_entries = current_user.bookshelf_entries.where(bookshelf: @source_bookshelf).profile_sorted("manual")
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
    if @organizing_bookshelf
      return transfer_user_library_path(@user, mode: "organize", source_bookshelf_id: source_bookshelf.id)
    end

    transfer_user_library_path(
      @user,
      source_bookshelf_id: source_bookshelf.id,
      target_bookshelf_id: target_bookshelf.id,
      changed:
    )
  end
  helper_method :transfer_path_for
end
