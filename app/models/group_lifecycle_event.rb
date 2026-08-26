class GroupLifecycleEvent < ApplicationRecord
  enum :event_type,
       {
         opening_requested: 0,
         opening_approved: 1,
         operations_closed: 2,
         reactivation_requested: 3,
         reactivation_approved: 4
       },
       validate: true

  belongs_to :group
  belongs_to :actor, class_name: "User", inverse_of: :group_lifecycle_events

  validates :detail, length: { maximum: 500 }, allow_nil: true
  validate :only_pending_opening_detail_can_change, on: :update

  private

  def only_pending_opening_detail_can_change
    allowed = opening_requested? && group.pending_approval? && group.closed_at.nil? &&
      will_save_change_to_detail? && (changes_to_save.keys - [ "detail" ]).empty?
    errors.add(:base, :invalid) unless allowed
  end
end
