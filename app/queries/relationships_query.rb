class RelationshipsQuery
  TABS = %w[book_friends received_book_friend_requests sent_book_friend_requests following_users followers].freeze
  PER_PAGE = 24

  attr_reader :tab, :query, :counts, :records, :page, :total_count, :total_pages

  def initialize(user:, tab: nil, query: nil, page: nil)
    @tab = TABS.include?(tab) ? tab : TABS.first
    @query = query.is_a?(String) ? query.strip : ""
    scopes = relationship_scopes(user)
    @counts = scopes.transform_values(&:count)
    scope = scopes.fetch(@tab)
    if @query.present?
      pattern = "%#{User.sanitize_sql_like(@query)}%"
      scope = scope.where("users.name ILIKE :pattern", pattern: pattern)
    end
    @total_count = @query.blank? ? counts.fetch(@tab) : scope.count
    @total_pages = [ (total_count.to_f / PER_PAGE).ceil, 1 ].max
    requested_page = Integer(page, exception: false).to_i
    @page = requested_page.clamp(1, total_pages)
    @records = ordered_records(scope).limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end

  def navigation_params
    { tab: tab, q: query.presence, page: page }.compact
  end

  def previous_page
    page - 1 if page > 1
  end

  def next_page
    page + 1 if page < total_pages
  end

  def first_item = total_count.zero? ? 0 : (page - 1) * PER_PAGE + 1
  def last_item = [ page * PER_PAGE, total_count ].min

  private

  def relationship_scopes(user)
    accepted = BookFriendship.accepted_only
    friends = User.where(id: accepted.where(requester: user).select(:addressee_id))
      .or(User.where(id: accepted.where(addressee: user).select(:requester_id)))

    {
      "book_friends" => friends,
      "received_book_friend_requests" => user.received_book_friendships.pending.joins(:requester),
      "sent_book_friend_requests" => user.requested_book_friendships.pending.joins(:addressee),
      "following_users" => user.followees,
      "followers" => user.followers
    }
  end

  def ordered_records(scope)
    case tab
    when "received_book_friend_requests"
      scope.order(created_at: :desc, id: :desc).includes(requester: { avatar_attachment: :blob })
    when "sent_book_friend_requests"
      scope.order(created_at: :desc, id: :desc).includes(addressee: { avatar_attachment: :blob })
    else
      scope.order(:name, :id).includes(avatar_attachment: :blob)
    end
  end
end
