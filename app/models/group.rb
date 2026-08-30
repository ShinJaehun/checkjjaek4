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

  belongs_to :group_admin, class_name: "User", inverse_of: :administered_groups
  has_many :group_memberships, dependent: :destroy
  has_many :group_membership_removals, dependent: :destroy
  has_many :group_membership_events, dependent: :delete_all
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

  after_create :create_group_admin_membership!

  def active_member?(user)
    user.present? && group_memberships.active.exists?(user: user)
  end

  def activity_allowed_for?(user)
    user.present? && group_memberships.active.where(user:).moderation_status_normal.exists?
  end

  def group_admin?(user)
    user.present? && group_admin_id == user.id
  end

  def transfer_admin_to!(new_admin, by:)
    with_lock do
      target_membership = new_admin && group_memberships.active.lock.find_by(user_id: new_admin.id)
      valid_transfer = admin_transfer_actor?(by) && (active? || inactive?) && new_admin.present? &&
        new_admin.id != group_admin_id && target_membership&.moderation_status_normal?

      unless valid_transfer
        errors.add(:group_admin, :invalid_admin_transfer)
        raise ActiveRecord::RecordInvalid.new(self)
      end

      update!(group_admin: new_admin)
    end
  end

  def cancel_pending_application_for_withdrawal!
    safe_memberships = group_memberships.where.not(user_id: group_admin_id).none? &&
      group_memberships.active.where(user_id: group_admin_id).exists?
    safe_events = lifecycle_events.where.not(event_type: :opening_requested).none? &&
      lifecycle_events.opening_requested.count <= 1

    unless pending_approval? && closed_at.nil? && !jjaeks.exists? && safe_memberships && safe_events
      errors.add(:base, :invalid)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    destroy!
  end

  def cancel_reactivation_for_withdrawal!
    unless pending_approval? && closed_at.present?
      errors.add(:base, :invalid)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    @cancelling_reactivation_for_withdrawal = true
    update!(lifecycle_status: :inactive)
  ensure
    @cancelling_reactivation_for_withdrawal = false
  end

  private

  def admin_transfer_actor?(actor)
    group_admin?(actor) || actor&.global_admin?
  end

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
    return if cancelling_reactivation_for_withdrawal?

    errors.add(:closure_reason, :blank)
  end

  def lifecycle_status_transition_must_be_valid
    return unless persisted? && will_save_change_to_lifecycle_status?
    return if lifecycle_status_change_to_be_saved.in?([
      %w[pending_approval active],
      %w[active inactive],
      %w[inactive pending_approval]
    ])
    return if cancelling_reactivation_for_withdrawal?

    errors.add(:lifecycle_status, :invalid_transition)
  end

  def create_group_admin_membership!
    group_memberships.create!(user: group_admin, status: :active)
    group_membership_events.create!(user: group_admin, actor: group_admin, event_type: :joined)
  end

  def cancelling_reactivation_for_withdrawal?
    @cancelling_reactivation_for_withdrawal == true
  end
end
