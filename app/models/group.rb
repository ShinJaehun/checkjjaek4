class Group < ApplicationRecord
  USER_CREATABLE_TYPES = %w[public_group approval_group private_group].freeze
  SUSPENSION_REASONS = %w[
    repeated_policy_violations
    facilitating_violations
    harassment_or_targeting
    spam_or_manipulation
    deceptive_operation
    other
  ].freeze

  def self.suspension_reason_label(reason)
    return reason unless SUSPENSION_REASONS.include?(reason)

    I18n.t("groups.operation_suspension_reasons.#{reason}")
  end

  enum :group_type,
       { public_group: 0, approval_group: 1, private_group: 2 },
       default: :public_group,
       validate: true
  enum :lifecycle_status,
       { pending_approval: 0, active: 1, inactive: 2, rejected: 3, cancelled: 4 },
       default: :pending_approval,
       validate: true

  belongs_to :group_admin, class_name: "User", inverse_of: :administered_groups
  has_many :group_memberships, dependent: :destroy
  has_many :group_membership_removals, dependent: :destroy
  has_many :group_membership_events, dependent: :delete_all
  has_many :group_member_bans, dependent: :destroy
  has_many :group_list_hidings, dependent: :delete_all
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
  after_update :restore_eligible_list_entries, if: -> { saved_change_to_lifecycle_status? || saved_change_to_operation_suspended_at? }

  scope :pending_opening_applications, -> { pending_approval.where(closed_at: nil) }
  scope :ended_applications, -> { where(lifecycle_status: %i[rejected cancelled]) }

  def pending_opening_application?
    pending_approval? && closed_at.nil?
  end

  def pending_reactivation_request?
    pending_approval? && closed_at.present?
  end

  def application_ended?
    rejected? || cancelled?
  end

  def to_param
    return unless persisted?

    slug = name.to_s.downcase.gsub(/[^\p{L}\p{N}]+/u, "-").gsub(/\A-+|-+\z/, "")
    slug.present? ? "#{id}-#{slug}" : id.to_s
  end

  def active_member?(user)
    user.present? && group_memberships.active.exists?(user: user)
  end

  def activity_allowed_for?(user)
    operation_active? && user.present? && group_memberships.active.where(user:).moderation_status_normal.exists?
  end

  def operation_suspended?
    operation_suspended_at.present?
  end

  def operation_active?
    !operation_suspended? && !application_ended?
  end

  def current_operation_suspension_action
    ModerationAction.current_group_operation_suspension_for(self)
  end

  def group_admin?(user)
    user.present? && group_admin_id == user.id
  end

  def member_banned?(user)
    user.present? && group_member_bans.exists?(user:)
  end

  def transfer_admin_to!(new_admin, by:)
    with_lock do
      previous_admin = group_admin
      target_membership = new_admin && group_memberships.active.lock.find_by(user_id: new_admin.id)
      valid_transfer = operation_active? && admin_transfer_actor?(by) && (active? || inactive?) && new_admin.present? &&
        new_admin.id != group_admin_id && target_membership&.moderation_status_normal?

      unless valid_transfer
        errors.add(:group_admin, :invalid_admin_transfer)
        raise ActiveRecord::RecordInvalid.new(self)
      end

      update!(group_admin: new_admin)
      revoked_event = group_membership_events.create!(user: previous_admin, actor: by, event_type: :admin_role_revoked)
      granted_event = group_membership_events.create!(user: new_admin, actor: by, event_type: :admin_role_granted)
      Notifications::GroupLifecycleNotifier.schedule(event: revoked_event, recipient_ids: [ previous_admin.id ])
      Notifications::GroupLifecycleNotifier.schedule(event: granted_event, recipient_ids: [ new_admin.id ])
      granted_event
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

  def restore_eligible_list_entries
    GroupListHiding.restore_eligible_for!(group_id: id)
  end

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
    return if ending_reactivation_request?
    return if cancelling_reactivation_for_withdrawal?

    errors.add(:closure_reason, :blank)
  end

  def lifecycle_status_transition_must_be_valid
    return unless persisted? && will_save_change_to_lifecycle_status?
    if lifecycle_status_in_database == "pending_approval" && closed_at_in_database.nil? && closed_at.nil? && application_ended?
      return
    end
    return if lifecycle_status_change_to_be_saved.in?([
      %w[pending_approval active],
      %w[active inactive],
      %w[inactive pending_approval]
    ])
    return if ending_reactivation_request?
    return if cancelling_reactivation_for_withdrawal?

    errors.add(:lifecycle_status, :invalid_transition)
  end

  def ending_reactivation_request?
    lifecycle_status_in_database == "pending_approval" && inactive? && closed_at_in_database.present? &&
      !will_save_change_to_closed_at? && !will_save_change_to_closure_reason?
  end

  def create_group_admin_membership!
    group_memberships.create!(user: group_admin, status: :active)
    group_membership_events.create!(user: group_admin, actor: group_admin, event_type: :joined)
  end

  def cancelling_reactivation_for_withdrawal?
    @cancelling_reactivation_for_withdrawal == true
  end
end
