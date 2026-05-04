class BookshelvesController < ApplicationController
  def create
    @bookshelf = current_user.bookshelves.build(bookshelf_params)
    @bookshelf.is_default = false
    authorize @bookshelf

    if @bookshelf.save
      redirect_to user_path(current_user, bookshelf_id: @bookshelf.id),
                  notice: t("bookshelves.notices.created", bookshelf_name: @bookshelf.name)
    else
      prepare_profile_after_create_failure
      render "users/show", status: :unprocessable_content
    end
  end

  private

  def bookshelf_params
    params.fetch(:bookshelf, {}).permit(:name, :visibility)
  end

  def prepare_profile_after_create_failure
    @user = current_user
    profile_policy = policy(@user)
    @book_friendship = nil
    @show_bookshelf = profile_policy.show_profile_bookshelf?
    @show_profile_bookshelf_status = profile_policy.show_profile_bookshelf_status?
    @show_profile_bookshelf_move_control = true
    @show_profile_bookshelf_create_form = true
    @profile_bookshelf_visibility_options = Bookshelf.visibilities.keys
    @profile_bookshelf_move_targets = current_user.bookshelves.default_first
    @profile_bookshelves = policy_scope(current_user.bookshelves).default_first
    visible_entries = policy_scope(current_user.bookshelf_entries, policy_scope_class: BookshelfEntryPolicy::ProfileScope)
    @profile_bookshelf_entry_counts = visible_entries.group(:bookshelf_id).count
    @selected_bookshelf = selected_profile_bookshelf(@profile_bookshelves)
    @bookshelf_entries = @selected_bookshelf ? visible_entries.where(bookshelf: @selected_bookshelf).recent_first : BookshelfEntry.none
    @profile_jjaek = Jjaek.new(user: current_user, target_user: current_user, visibility: :public_jjaek)
    @profile_jjaek_visibility_options = %w[public_jjaek book_friends private_jjaek]
    @book_activities = policy_scope(BookActivity).where(user: current_user).includes(:user, :book).recent
    @jjaeks = policy_scope(current_user.jjaeks).includes(:user, :book, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book ]).recent
    prepare_visible_requote_counts_for(@jjaeks)
    @profile_activity_items = (@jjaeks.to_a + @book_activities.to_a).sort_by(&:created_at).reverse
    @show_profile_activity = true
  end

  def selected_profile_bookshelf(accessible_bookshelves)
    bookshelves = accessible_bookshelves.to_a
    requested_bookshelf = bookshelves.find { |bookshelf| bookshelf.id.to_s == params[:bookshelf_id].to_s }

    requested_bookshelf || bookshelves.find(&:is_default?) || bookshelves.first
  end
end
