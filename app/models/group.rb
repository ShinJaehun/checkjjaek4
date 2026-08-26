class Group < ApplicationRecord
  USER_CREATABLE_TYPES = %w[public_group approval_group private_group].freeze

  enum :group_type,
       { public_group: 0, approval_group: 1, private_group: 2 },
       default: :public_group,
       validate: true
  enum :lifecycle_status,
       { pending_approval: 0, active: 1, inactive: 2 },
       default: :pending_approval,
       validate: true

  belongs_to :owner, class_name: "User", inverse_of: :owned_groups
  has_many :group_memberships, dependent: :destroy
  has_many :active_group_memberships, -> { active }, class_name: "GroupMembership"
  has_many :members, through: :active_group_memberships, source: :user
  has_many :jjaeks, dependent: :restrict_with_error
  has_many :lifecycle_events,
           -> { order(:created_at, :id) },
           class_name: "GroupLifecycleEvent",
           dependent: :destroy,
           inverse_of: :group

  validates :name, presence: true
  validates :application_purpose, length: { maximum: 500 }, allow_nil: true
  validates :closure_reason, length: { maximum: 500 }, allow_nil: true
  validate :application_purpose_must_be_present_for_new_application
  validate :existing_application_purpose_cannot_be_removed
  validate :closure_reason_must_be_present_when_closing
  validate :lifecycle_status_transition_must_be_valid

  after_create :create_owner_membership!

  def active_member?(user)
    user.present? && group_memberships.active.exists?(user: user)
  end

  def owner?(user)
    user.present? && owner_id == user.id
  end

  private

  def application_purpose_must_be_present_for_new_application
    return unless new_record? && pending_approval? && application_purpose.blank?

    errors.add(:application_purpose, :blank)
  end

  def existing_application_purpose_cannot_be_removed
    return unless persisted? && will_save_change_to_application_purpose?
    return unless application_purpose_in_database.present? && application_purpose.blank?

    errors.add(:application_purpose, :blank)
  end

  def closure_reason_must_be_present_when_closing
    return unless will_save_change_to_lifecycle_status? && inactive? && closure_reason.blank?

    errors.add(:closure_reason, :blank)
  end

  def lifecycle_status_transition_must_be_valid
    return unless persisted? && will_save_change_to_lifecycle_status?
    return if lifecycle_status_change_to_be_saved.in?([
      %w[pending_approval active],
      %w[active inactive],
      %w[inactive pending_approval]
    ])

    errors.add(:lifecycle_status, :invalid_transition)
  end

  def create_owner_membership!
    group_memberships.create!(user: owner, status: :active)
  end
end
