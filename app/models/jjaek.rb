class Jjaek < ApplicationRecord
  MODERATION_HIDE_REASONS = %w[
    inappropriate_content
    spam_advertising
    personal_information
    service_disruption
    other
  ].freeze

  enum :visibility, { public_jjaek: 0, book_friends: 1, private_jjaek: 2 },
       default: :public_jjaek,
       validate: true

  belongs_to :user
  belongs_to :book, optional: true
  belongs_to :group, optional: true
  belongs_to :quoted_jjaek, class_name: "Jjaek", optional: true
  belongs_to :target_user, class_name: "User", optional: true, inverse_of: :targeted_jjaeks

  has_many :requotes, class_name: "Jjaek", foreign_key: :quoted_jjaek_id, inverse_of: :quoted_jjaek
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :moderation_actions, as: :target

  before_destroy :mark_requotes_as_deleted_source

  validates :content, presence: true, length: { maximum: 2_000 }, unless: :deleted?
  validates :quoted_jjaek_id,
            uniqueness: { scope: :user_id },
            allow_nil: true
  validate :quoted_jjaek_must_be_requotable
  validate :quoted_jjaek_must_not_be_requote
  validate :quoted_group_jjaek_must_be_public
  validate :quoted_jjaek_visibility_must_not_expand
  validate :target_user_visibility_must_not_be_private
  validate :group_context_must_not_be_requote
  validate :group_context_must_not_target_user

  before_validation :normalize_group_visibility
  before_update :record_content_edited_at

  scope :recent, -> { order(created_at: :desc) }
  scope :visible, -> { where(hidden_at: nil) }

  def requote?
    quoted_jjaek_id.present? || quoted_source_deleted?
  end

  def quoted_source_deleted?
    quoted_source_deleted_at.present?
  end

  def deleted?
    deleted_at.present?
  end

  def hidden?
    hidden_at.present?
  end

  def current_hide_action
    ModerationAction.current_hide_for(self)
  end

  def destroy_or_tombstone!
    return destroy! unless comments.exists?

    transaction do
      deletion_time = Time.current
      mark_requotes_as_deleted_source(deletion_time)
      update_columns(content: "", deleted_at: deletion_time, updated_at: deletion_time)
    end
  end

  def comments_count
    safe_association_count(:comments)
  end

  def likes_count
    safe_association_count(:likes)
  end

  private

  # association이 이미 로드된 상태에서는 form용 unsaved 객체가 target에 섞일 수 있다.
  # 화면 메타 카운트는 항상 persisted 레코드 기준으로 맞춘다.
  def safe_association_count(name)
    association_proxy = association(name)

    if association_proxy.loaded?
      public_send(name).count(&:persisted?)
    else
      public_send(name).count
    end
  end

  def record_content_edited_at
    self.content_edited_at = Time.current if will_save_change_to_content? && !will_save_change_to_deleted_at?
  end

  def mark_requotes_as_deleted_source(deletion_time = Time.current)
    requotes.update_all(
      quoted_jjaek_id: nil,
      quoted_source_author_name: user.name,
      quoted_source_deleted_at: deletion_time,
      quoted_source_kind: book.present? ? "book" : "general",
      visibility: self.class.visibilities[:private_jjaek],
      updated_at: deletion_time
    )
  end

  def quoted_jjaek_must_be_requotable
    return unless quoted_jjaek.present?
    return unless quoted_jjaek.private_jjaek?

    errors.add(:quoted_jjaek, :invalid)
  end

  def quoted_jjaek_must_not_be_requote
    return unless quoted_jjaek&.requote?

    errors.add(:quoted_jjaek, :invalid)
  end

  def quoted_group_jjaek_must_be_public
    return unless quoted_jjaek&.group_id.present?
    return if quoted_jjaek.group.public_group?

    errors.add(:quoted_jjaek, :invalid)
  end

  def quoted_jjaek_visibility_must_not_expand
    return unless quoted_jjaek.present?
    return if visibility_rank >= quoted_jjaek.send(:visibility_rank)

    errors.add(:visibility, :cannot_exceed_quoted_visibility)
  end

  def target_user_visibility_must_not_be_private
    return unless target_user_id.present?
    return if target_user_id == user_id
    return unless private_jjaek?

    errors.add(:visibility, :invalid)
  end

  def visibility_rank
    case visibility
    when "public_jjaek" then 0
    when "book_friends" then 1
    else 2
    end
  end

  def normalize_group_visibility
    self.visibility = :public_jjaek if group_id.present?
  end

  def group_context_must_not_be_requote
    return unless group_id.present? && quoted_jjaek_id.present?

    errors.add(:quoted_jjaek, :invalid)
  end

  def group_context_must_not_target_user
    return unless group_id.present? && target_user_id.present?

    errors.add(:target_user, :invalid)
  end
end
