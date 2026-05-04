class Users::LibrariesController < ApplicationController
  def show
    @user = User.find(params[:user_id])
    authorize @user, :show?
    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    prepare_library_bookshelf(policy(@user))
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
    @profile_bookshelf_move_targets = @show_profile_bookshelf_move_control ? current_user.bookshelves.default_first : Bookshelf.none

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

  def library_bookshelf_sort
    BookshelfEntry::PROFILE_SORTS.include?(params[:sort]) ? params[:sort] : "recent"
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
end
