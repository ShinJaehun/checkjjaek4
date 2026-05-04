class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    authorize @user, :show?
    prepare_profile_context
  end

  private

  def prepare_profile_context
    profile_policy = policy(@user)

    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    prepare_profile_bookshelf(profile_policy)
    prepare_profile_book_activities
    prepare_profile_jjaeks(profile_policy)
    prepare_profile_activity_items
    prepare_profile_jjaek_form(profile_policy)
  end

  def prepare_profile_bookshelf(profile_policy)
    @show_bookshelf = profile_policy.show_profile_bookshelf?
    @show_profile_bookshelf_status = profile_policy.show_profile_bookshelf_status?
    @show_library_link = profile_policy.show_library?
    @show_profile_bookshelf_detail = @show_library_link
    @show_profile_bookshelf_move_control = current_user == @user
    @show_profile_bookshelf_create_form = current_user == @user
    @bookshelf ||= current_user.bookshelves.build(visibility: :public, color_key: "stone") if @show_profile_bookshelf_create_form
    @profile_bookshelf_visibility_options = Bookshelf.visibilities.keys
    @profile_bookshelf_color_options = Bookshelf::COLOR_KEYS
    @profile_bookshelf_sort = profile_bookshelf_sort
    @profile_bookshelf_sort_options = BookshelfEntry::PROFILE_SORTS
    @profile_bookshelf_move_targets = @show_profile_bookshelf_move_control ? current_user.bookshelves.default_first : Bookshelf.none

    return unless @show_bookshelf

    visible_entries = policy_scope(@user.bookshelf_entries, policy_scope_class: BookshelfEntryPolicy::ProfileScope)

    unless @show_profile_bookshelf_detail
      @profile_public_bookshelf_entries = visible_entries
        .joins(:bookshelf)
        .where(bookshelves: { visibility: "public" })
        .profile_sorted("recent")
      return
    end

    @profile_bookshelves = policy_scope(@user.bookshelves).default_first
    @profile_bookshelf_entry_counts = visible_entries.group(:bookshelf_id).count
    @selected_bookshelf = selected_profile_bookshelf(@profile_bookshelves)
    @managed_bookshelf ||= @selected_bookshelf if @show_profile_bookshelf_create_form && @selected_bookshelf&.is_default? == false
    @profile_bookshelf_order_controls = @show_profile_bookshelf_create_form ? bookshelf_order_controls(@profile_bookshelves) : {}
    @bookshelf_entries =
      if @selected_bookshelf
        visible_entries.where(bookshelf: @selected_bookshelf).profile_sorted(@profile_bookshelf_sort)
      else
        BookshelfEntry.none
      end
  end

  def profile_bookshelf_sort
    BookshelfEntry::PROFILE_SORTS.include?(params[:sort]) ? params[:sort] : "recent"
  end

  def selected_profile_bookshelf(accessible_bookshelves)
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

  def prepare_profile_jjaeks(profile_policy)
    @show_jjaeks = profile_policy.show_profile_jjaeks?
    @jjaeks =
      if @show_jjaeks
        resolve_profile_jjaeks(profile_policy.profile_access_level)
      else
        Jjaek.none
      end
    prepare_visible_requote_counts_for(@jjaeks)
  end

  def prepare_profile_book_activities
    @book_activities = policy_scope(BookActivity)
      .where(user: @user)
      .includes(:user, :book)
      .recent
  end

  def prepare_profile_jjaek_form(profile_policy)
    return unless profile_policy.write_profile_jjaek?

    @profile_jjaek = Jjaek.new(
      user: current_user,
      target_user: @user,
      visibility: profile_jjaek_default_visibility
    )
    @profile_jjaek_visibility_options = profile_jjaek_visibility_options
  end

  def profile_jjaek_default_visibility
    current_user == @user ? :public_jjaek : :book_friends
  end

  def profile_jjaek_visibility_options
    options = %w[public_jjaek book_friends]
    options << "private_jjaek" if current_user == @user
    options
  end

  def resolve_profile_jjaeks(access_level)
    scope = policy_scope(@user.jjaeks).includes(:user, :book, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book ])

    case access_level
    when :none, :following
      # stranger와 follow는 public_jjaek만
      scope.where(visibility: Jjaek.visibilities[:public_jjaek]).recent
    else
      scope.recent
    end
  end

  def prepare_profile_activity_items
    @profile_activity_items = (@jjaeks.to_a + @book_activities.to_a).sort_by(&:created_at).reverse
    @show_profile_activity = @show_jjaeks || current_user == @user || @profile_activity_items.any?
  end
end
