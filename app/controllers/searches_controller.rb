class SearchesController < ApplicationController
  POST_TYPES = %w[jjaeks].freeze
  RESULT_TYPES = %w[users jjaeks groups].freeze
  PREVIEW_LIMIT = 5

  def show
    authorize :search, :show?
    @tag_mode = params.key?(:tag)
    @tag_input = params[:tag].to_s.strip.delete_prefix("#") if @tag_mode
    @tag = Tag.canonical_name(@tag_input) if @tag_mode
    prepare_tag_scope! if @tag_mode
    @query = params[:q].to_s.strip
    available_types = @tag_mode ? POST_TYPES : RESULT_TYPES
    requested_type = params[:type]
    requested_type = "jjaeks" if requested_type.in?(%w[book_jjaeks recommendation_jjaeks])
    @type = requested_type.in?(available_types) ? requested_type : "all"
    @per_page = Admin::InventoryPage.normalize_per_page(params[:per_page])
    unless @tag_mode
      tag_context_requested = %i[scope group_id user_id].any? { |key| params.key?(key) }
      hashtag = Tag::HASHTAG_PATTERN.match(@query)
      if hashtag && hashtag[0] == @query && (name = Tag.canonical_name(hashtag[1]))
        type = @type.in?(POST_TYPES) ? @type : "all"
        tag_params = { tag: name, type:, per_page: @per_page }
        if tag_context_requested
          prepare_tag_scope!
          tag_params.merge!(scope: @tag_scope, group_id: @tag_group&.id, user_id: @tag_user&.id)
        end
        return redirect_to search_path(tag_params.compact)
      end
      return redirect_to search_path(q: @query.presence, type: @type, per_page: @per_page) if tag_context_requested
    end
    @results = {}
    if !@tag_mode && @query.blank?
      prepare_popular_tags
      return
    end
    return if @tag_mode && @tag.blank?

    types = @type == "all" ? available_types : [ @type ]
    types.each do |type|
      scope = results_for(type)
      @results[type] = if @type == "all"
        scope.limit(PREVIEW_LIMIT).load
      else
        @result_page = Admin::InventoryPage.new(scope, page: params[:page], per_page: @per_page)
        @result_page.records.load
      end
    end
    prepare_user_cards
    prepare_group_cards
    posts = @results.fetch("jjaeks", []).to_a
    prepare_attached_books_for(posts)
    prepare_current_reading_states_for(posts)
  end

  private

  def prepare_popular_tags
    visible_jjaek_ids = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::SearchScope).select(:id)
    count_sql = "COUNT(DISTINCT jjaek_tags.jjaek_id)"
    tags = JjaekTag.joins(:tag)
      .where(jjaek_id: visible_jjaek_ids)
      .group("tags.id", "tags.name")
      .having("#{count_sql} >= 2")
      .order(Arel.sql("#{count_sql} DESC"), "tags.name ASC")
      .limit(8)
      .pluck("tags.name")
    @popular_tags = tags if tags.size >= 3
  end

  def prepare_tag_scope!
    @tag_scope = params[:scope].presence || "all"
    raise ActiveRecord::RecordNotFound unless @tag_scope.in?(%w[all group user])
    raise ActiveRecord::RecordNotFound if params.key?(:group_id) && params.key?(:user_id)

    if params.key?(:group_id)
      group_id = params[:group_id]
      raise ActiveRecord::RecordNotFound unless group_id.is_a?(String) && group_id.match?(/\A[1-9]\d*\z/)

      @tag_group = Group.find(group_id)
      raise ActiveRecord::RecordNotFound unless policy(@tag_group).read_jjaeks?
    end
    if params.key?(:user_id)
      user_id = params[:user_id]
      raise ActiveRecord::RecordNotFound unless user_id.is_a?(String) && user_id.match?(/\A[1-9]\d*\z/)

      @tag_user = User.find(user_id)
      raise ActiveRecord::RecordNotFound unless policy(@tag_user).show? && policy(@tag_user).show_profile_jjaeks?
    end

    raise ActiveRecord::RecordNotFound if @tag_scope == "group" && !@tag_group
    raise ActiveRecord::RecordNotFound if @tag_scope == "user" && !@tag_user
  end

  def results_for(type)
    case type
    when "users"
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      policy_scope(User, policy_scope_class: UserPolicy::SearchScope)
        .where("users.name ILIKE :pattern OR users.handle ILIKE :pattern", pattern:)
        .select(:id, :name, :handle, :withdrawn_at, :default_avatar_index)
        .includes(avatar_attachment: :blob)
        .order(:name, :id)
    when "groups"
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      policy_scope(Group, policy_scope_class: GroupPolicy::NameSearchScope)
        .where("groups.name ILIKE ?", pattern)
        .select(:id, :name, :group_type)
        .order(:name, :id)
    when *POST_TYPES
      posts = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::SearchScope)
        .includes(:attached_books, :group,
                  user: { avatar_attachment: :blob },
                  target_user: { avatar_attachment: :blob },
                  quoted_jjaek: [ :attached_books, :group, { user: { avatar_attachment: :blob } } ])
        .order(created_at: :desc, id: :desc)
      if @tag_mode
        tagged_ids = JjaekTag.joins(:tag).where(tags: { name: @tag }).select(:jjaek_id)
        posts = posts.where(id: tagged_ids)
        posts = posts.where(group_id: @tag_group.id) if @tag_scope == "group"
        posts = posts.where(user_id: @tag_user.id) if @tag_scope == "user"
      else
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        posts = posts.where("jjaeks.content ILIKE ?", pattern)
      end
      posts
    end
  end

  def prepare_user_cards
    user_ids = @results.fetch("users", []).map(&:id)
    return if user_ids.empty?

    @search_book_friend_ids = BookFriendship.accepted_only
      .where(requester_id: current_user.id, addressee_id: user_ids)
      .or(BookFriendship.accepted_only.where(addressee_id: current_user.id, requester_id: user_ids))
      .pluck(:requester_id, :addressee_id).flatten.uniq
    @search_following_ids = Follow.where(follower: current_user, followee_id: user_ids).pluck(:followee_id)
    @search_follower_ids = Follow.where(followee: current_user, follower_id: user_ids).pluck(:follower_id)
    @search_follower_counts = Follow.where(followee_id: user_ids).group(:followee_id).count
    @search_following_counts = Follow.where(follower_id: user_ids).group(:follower_id).count
  end

  def prepare_group_cards
    @search_group_details = {}
    @search_group_member_counts = {}
    @search_group_member_previews = {}
    group_ids = @results.fetch("groups", []).map(&:id)
    return if group_ids.empty?

    @search_group_details = policy_scope(Group).where(id: group_ids)
      .includes(group_admin: { avatar_attachment: :blob }).index_by(&:id)
    return if @search_group_details.empty?

    GroupMembership.card_previews_for(group_ids: @search_group_details.keys).each do |membership|
      @search_group_member_counts[membership.group_id] = membership[:active_member_count].to_i
      (@search_group_member_previews[membership.group_id] ||= []) << membership.user
    end
  end
end
