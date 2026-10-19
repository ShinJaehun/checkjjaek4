class FeedPage
  SIZE = 20
  class InvalidCursor < StandardError; end

  attr_reader :items, :next_cursor

  def initialize(jjaeks:, book_activities: nil, cursor: nil)
    boundary = decode(cursor) unless cursor.nil? || cursor == ""
    candidates = records_after(jjaeks, 1, boundary)
    candidates.concat(records_after(book_activities, 0, boundary)) if book_activities
    candidates.sort_by! { |record| [ record.created_at, record.is_a?(Jjaek) ? 1 : 0, record.id ] }
    candidates.reverse!
    @items = candidates.first(SIZE)
    @next_cursor = encode(@items.last) if candidates.size > SIZE
  end

  private

  def records_after(scope, rank, boundary)
    if boundary
      time, cursor_rank, id = boundary
      table = scope.klass.arel_table
      older = table[:created_at].lt(time)
      tied = table[:created_at].eq(time)
      older = older.or(tied) if rank < cursor_rank
      older = older.or(tied.and(table[:id].lt(id))) if rank == cursor_rank
      scope = scope.where(older)
    end
    scope.reorder(created_at: :desc, id: :desc).limit(SIZE + 1).to_a
  end

  def encode(record)
    verifier.generate([ record.created_at.iso8601(6), record.is_a?(Jjaek) ? 1 : 0, record.id ])
  end

  def decode(cursor)
    raise InvalidCursor unless cursor.is_a?(String) && cursor.bytesize <= 1024

    values = verifier.verified(cursor)
    unless values.is_a?(Array) && values.size == 3 && values[0].is_a?(String) &&
        [ 0, 1 ].include?(values[1]) && values[2].is_a?(Integer) && values[2].positive?
      raise InvalidCursor
    end
    [ Time.iso8601(values[0]), values[1], values[2] ]
  rescue ArgumentError
    raise InvalidCursor
  end

  def verifier
    Rails.application.message_verifier("feed-pagination")
  end
end
