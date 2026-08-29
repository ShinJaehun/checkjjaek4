module Admin
  class UserAccountHistoryQuery
    HistoryEntry = Struct.new(:event_type, :occurred_at, :action, keyword_init: true)

    def initialize(user)
      @user = user
    end

    def call
      entries = [ HistoryEntry.new(event_type: :joined, occurred_at: user.created_at) ]
      entries.concat(moderation_entries)
      entries << HistoryEntry.new(event_type: :withdrawn, occurred_at: user.withdrawn_at) if user.withdrawn?
      entries.sort_by { |entry| [ entry.occurred_at, tie_breaker(entry) ] }
    end

    private

    attr_reader :user

    def tie_breaker(entry)
      return 0 if entry.event_type == :joined
      return entry.action.id if entry.action

      Float::INFINITY
    end

    def moderation_entries
      ModerationAction.where(target: user, action_type: %i[suspend restore])
        .includes(:actor)
        .order(:created_at, :id)
        .map do |action|
          HistoryEntry.new(
            event_type: action.action_type_suspend? ? :suspended : :restored,
            occurred_at: action.created_at,
            action:
          )
        end
    end
  end
end
