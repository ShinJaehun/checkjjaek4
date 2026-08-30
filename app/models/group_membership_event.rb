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
         removed: 10
       },
       validate: true

  belongs_to :group
  belongs_to :user, inverse_of: :group_membership_events
  belongs_to :actor, class_name: "User", inverse_of: :performed_group_membership_events

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def readonly?
    persisted? || super
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is append-only" if persisted?

    super
  end
end
