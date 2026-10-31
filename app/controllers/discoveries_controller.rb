class DiscoveriesController < ApplicationController
  def show
    authorize :discovery, :show?
    @publication_date = Time.current.in_time_zone("Asia/Seoul").to_date
    @publication_cutoff = @publication_date.in_time_zone("Asia/Seoul").beginning_of_day

    prepare_book_jjaeks
    prepare_general_jjaeks
    prepare_recommended_library
    prepare_recommended_group
  end

  private

  def prepare_book_jjaeks
    @book = daily_order(Book.where(id: public_original_jjaeks.where.not(book_id: nil).select(:book_id))).first
    @book_jjaeks = @book ? varied_jjaeks(public_original_jjaeks.where(book_id: @book.id)) : []
    prepare_current_reading_states_for(@book_jjaeks)
  end

  def prepare_general_jjaeks
    @general_jjaeks = varied_jjaeks(public_original_jjaeks.where(book_id: nil).where.not(user_id: current_user.id))
  end

  def public_original_jjaeks
    @public_original_jjaeks ||= policy_scope(Jjaek)
      .where(group_id: nil, visibility: :public_jjaek, hidden_at: nil, deleted_at: nil,
             quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
      .where("jjaeks.created_at < ?", @publication_cutoff)
  end

  def varied_jjaeks(scope)
    author_ids = daily_order(User.where(id: scope.select(:user_id))).limit(3).pluck(:id)
    selected = author_ids.filter_map do |author_id|
      daily_order(scope.where(user_id: author_id)).first
    end
    if selected.size < 3
      selected.concat(daily_order(scope.where.not(id: selected.map(&:id)))
        .limit(3 - selected.size).to_a)
    end
    ActiveRecord::Associations::Preloader.new(
      records: selected, associations: { user: { avatar_attachment: :blob } }
    ).call
    selected
  end

  def daily_order(scope)
    table = scope.klass.connection.quote_table_name(scope.klass.table_name)
    seed = scope.klass.connection.quote("#{@publication_date.iso8601}:")
    scope.reorder(Arel.sql("md5(#{seed} || #{table}.id::text) ASC"), scope.klass.arel_table[:id].asc)
  end

  def prepare_recommended_library
    public_entries = policy_scope(BookshelfEntry, policy_scope_class: BookshelfEntryPolicy::ProfileScope)
      .joins(:bookshelf)
      .where(bookshelves: { visibility: "public" })
    @library_user = daily_order(User.active_accounts.where(suspended_at: nil)
      .where.not(id: current_user.id)
      .where(id: public_entries.select(:user_id))).first
    return unless @library_user

    entries = public_entries.where(user_id: @library_user.id)
    @public_book_count = entries.count
    @public_book_entries = entries.includes(:book).order(updated_at: :desc, id: :desc).limit(4)
  end

  def prepare_recommended_group
    candidates = policy_scope(Group)
      .where(lifecycle_status: :active, group_type: %i[public_group approval_group], operation_suspended_at: nil)
    joined_group_ids = current_user.group_memberships.active.select(:group_id)
    recommendable_groups = Group.where(id: candidates.select(:id))
    @group = daily_order(recommendable_groups.where.not(id: joined_group_ids)).first ||
      daily_order(recommendable_groups).first
    return unless @group

    @group_member_count = @group.active_group_memberships.where.not(user_id: @group.group_admin_id).count
    @group_member_preview = @group.active_group_memberships
      .where.not(user_id: @group.group_admin_id)
      .includes(user: { avatar_attachment: :blob })
      .order(:created_at, :id)
      .limit(5)
      .map(&:user)

    @can_read_group_posts = policy(@group).read_jjaeks?
    return unless @can_read_group_posts

    group_posts = policy_scope(@group.jjaeks, policy_scope_class: JjaekPolicy::GroupContentScope)
      .where(hidden_at: nil, deleted_at: nil)
    readable_source_ids = policy_scope(Jjaek).where(hidden_at: nil, deleted_at: nil).select(:id)
    readable_posts = group_posts.where(quoted_jjaek_id: nil, quoted_source_deleted_at: nil)
      .or(group_posts.where(quoted_jjaek_id: readable_source_ids))
    @group_posts = readable_posts.where("jjaeks.created_at < ?", @publication_cutoff)
      .includes(:book, user: { avatar_attachment: :blob })
      .order(created_at: :desc, id: :desc)
      .limit(3)
      .to_a
    prepare_current_reading_states_for(@group_posts)
  end
end
