class GroupMembershipEvent < ApplicationRecord
  enum :event_type,
       {
         joined: 0,
         requested_to_join: 1,
         join_request_cancelled: 2,
         approved: 3,
         request_rejected: 4,
         invited: 5,
         invitation_accepted: 6,
         invitation_declined: 7,
         invitation_revoked: 8,
         left: 9,
         removed: 10,
         admin_role_revoked: 11,
         admin_role_granted: 12
       },
       validate: true

  belongs_to :group
  belongs_to :user, inverse_of: :group_membership_events
  belongs_to :actor, class_name: "User", inverse_of: :performed_group_membership_events

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :participations, -> {
    where(event_type: %i[joined approved invitation_accepted left removed admin_role_revoked admin_role_granted])
  }

  # A ban deletes the membership, but retains this attribution even after unban.
  def self.ban_history_for(user)
    ModerationAction.where(membership_user_id: user.id, action_type: :ban_from_group)
  end

  def self.past_states_for(user:, groups:)
    group_ids = groups.map(&:id)
    events = participations.where(user:, group_id: group_ids)
      .select("DISTINCT ON (group_id) group_membership_events.*")
      .order(:group_id, created_at: :desc, id: :desc).index_by(&:group_id)
    ban_times = ban_history_for(user).where(membership_group_id: group_ids)
      .group(:membership_group_id).maximum(:created_at)
    banned_group_ids = GroupMemberBan.where(user:, group_id: group_ids).pluck(:group_id)

    states = groups.index_with do |group|
      event = events[group.id]
      ban_time = ban_times[group.id]
      status = if banned_group_ids.include?(group.id)
        "banned"
      elsif event && (!ban_time || event.created_at > ban_time) && event.event_type.in?(%w[left removed])
        event.event_type
      else
        "former"
      end
      { status:, ended_at: [ event&.created_at, ban_time ].compact.max }
    end.transform_keys(&:id)
    states.sort_by { |group_id, state| [ state.fetch(:ended_at), group_id ] }.reverse.to_h
  end

  def readonly?
    persisted? || super
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is append-only" if persisted?

    super
  end
end
