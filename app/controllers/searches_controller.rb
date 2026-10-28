class SearchesController < ApplicationController
  RESULT_TYPES = %w[users jjaeks book_jjaeks groups].freeze
  PREVIEW_LIMIT = 5

  def show
    authorize :search, :show?
    @query = params[:q].to_s.strip
    @type = params[:type].in?(RESULT_TYPES) ? params[:type] : "all"
    @per_page = Admin::InventoryPage.normalize_per_page(params[:per_page])
    @results = {}
    return if @query.blank?

    types = @type == "all" ? RESULT_TYPES : [ @type ]
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
    prepare_current_reading_states_for(@results.fetch("jjaeks", []).to_a + @results.fetch("book_jjaeks", []).to_a)
  end

  private

  def results_for(type)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"

    case type
    when "users"
      policy_scope(User, policy_scope_class: UserPolicy::SearchScope)
        .where("users.name ILIKE :pattern OR users.handle ILIKE :pattern", pattern:)
        .select(:id, :name, :handle, :withdrawn_at, :default_avatar_index)
        .includes(avatar_attachment: :blob)
        .order(:name, :id)
    when "groups"
      policy_scope(Group, policy_scope_class: GroupPolicy::NameSearchScope)
        .where("groups.name ILIKE ?", pattern)
        .select(:id, :name, :group_type)
        .order(:name, :id)
    when "jjaeks", "book_jjaeks"
      posts = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::SearchScope)
        .where("jjaeks.content ILIKE ?", pattern)
        .includes(:book, user: { avatar_attachment: :blob })
        .order(created_at: :desc, id: :desc)
      type == "jjaeks" ? posts.where(book_id: nil) : posts.where.not(book_id: nil)
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
