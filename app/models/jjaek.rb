class Jjaek < ApplicationRecord
  MAX_RECOMMENDATION_BOOKS = 5
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
  has_many :jjaek_tags, dependent: :delete_all
  has_many :tags, through: :jjaek_tags
  has_many :jjaek_recommendations, -> { order(:position) }, dependent: :destroy,
           inverse_of: :jjaek, autosave: true
  has_many :recommended_books, through: :jjaek_recommendations, source: :book
  has_many :moderation_actions, as: :target

  before_destroy :mark_requotes_as_deleted_source

  normalizes :content, with: ->(content) { content.gsub(/\r\n?/, "\n") }

  validates :content, presence: true, length: { maximum: 200 }, unless: :deleted?
  validates :quoted_jjaek_id,
            uniqueness: { scope: %i[user_id group_id] },
            allow_nil: true
  validate :quoted_jjaek_must_be_requotable
  validate :quoted_jjaek_must_not_be_requote
  validate :quoted_group_jjaek_must_be_public
  validate :quoted_jjaek_visibility_must_not_expand
  validate :target_user_visibility_must_not_be_private
  validate :quoted_group_context_must_be_allowed
  validate :group_context_must_not_target_user
  validate :recommendation_context_must_be_valid

  before_validation :normalize_group_visibility
  before_update :record_content_edited_at
  after_save :refresh_tags!, if: :saved_change_to_content?

  scope :recent, -> { order(created_at: :desc) }
  scope :visible, -> { where(hidden_at: nil) }
  scope :general_posts, -> { where(recommendation: false, book_id: nil) }
  scope :recommendation_posts, -> { where(recommendation: true) }

  def content_kind
    return "recommendation" if recommendation?

    book_id.present? ? "book" : "general"
  end

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
      jjaek_tags.delete_all
    end
  end

  # Replace links together so reordering cannot collide with existing positions.
  # The caller holds this Jjaek's lock (and the Group lock when applicable).
  def update_recommendation_books(books:, attributes:)
    transaction(requires_new: true) do
      jjaek_recommendations.delete_all
      association(:jjaek_recommendations).reset
      books.each_with_index do |book, position|
        jjaek_recommendations.build(book: book, position: position)
      end
      assign_attributes(attributes)
      save!
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey
    errors.add(:base, :invalid)
    false
  end

  def refresh_tags!
    tag_ids = deleted? ? [] : Tag.extract_names(content).map { |name| Tag.create_or_find_by!(name:).id }
    if tag_ids.empty?
      jjaek_tags.delete_all
    else
      jjaek_tags.where.not(tag_id: tag_ids).delete_all
      tag_ids.each { |tag_id| jjaek_tags.create_or_find_by!(tag_id:) }
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
    requotes.where(group_id: nil).update_all(
      quoted_jjaek_id: nil,
      quoted_source_author_name: user.name,
      quoted_source_deleted_at: deletion_time,
      quoted_source_kind: content_kind,
      visibility: self.class.visibilities[:private_jjaek],
      updated_at: deletion_time
    )

    requotes.where.not(group_id: nil).update_all(
      quoted_jjaek_id: nil,
      quoted_source_author_name: nil,
      quoted_source_deleted_at: deletion_time,
      quoted_source_kind: nil,
      visibility: self.class.visibilities[:public_jjaek],
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
    return if group_id.present? && group_id == quoted_jjaek.group_id
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

  def quoted_group_context_must_be_allowed
    return unless group_id.present? && quoted_jjaek.present?
    return if quoted_jjaek.group_id == group_id
    return if quoted_jjaek.group_id.blank? && quoted_jjaek.public_jjaek?

    errors.add(:quoted_jjaek, :invalid)
  end

  def group_context_must_not_target_user
    return unless group_id.present? && target_user_id.present?

    errors.add(:target_user, :invalid)
  end

  def recommendation_context_must_be_valid
    if recommendation?
      errors.add(:base, :invalid) if book.present? || requote? || target_user.present?
      links = jjaek_recommendations.reject(&:marked_for_destruction?)
      errors.add(:recommended_books, :blank) if links.empty?
      if links.size > MAX_RECOMMENDATION_BOOKS
        errors.add(:recommended_books, :too_many_recommendations, count: MAX_RECOMMENDATION_BOOKS)
      end
      books = links.map { |link| link.book_id || link.book }
      errors.add(:recommended_books, :taken) if books.uniq.size != books.size
    elsif jjaek_recommendations.any?
      errors.add(:recommended_books, :invalid)
    end
  end
end
