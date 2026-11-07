class Jjaek < ApplicationRecord
  MAX_ATTACHED_BOOKS = 5
  UNCHANGED_BOOKS = Object.new.freeze
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
  belongs_to :group, optional: true
  belongs_to :quoted_jjaek, class_name: "Jjaek", optional: true
  belongs_to :target_user, class_name: "User", optional: true, inverse_of: :targeted_jjaeks

  has_many :requotes, class_name: "Jjaek", foreign_key: :quoted_jjaek_id, inverse_of: :quoted_jjaek
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :jjaek_tags, dependent: :delete_all
  has_many :tags, through: :jjaek_tags
  has_many :jjaek_book_attachments, -> { order(:position) }, dependent: :destroy,
           inverse_of: :jjaek, autosave: true
  has_many :attached_books, through: :jjaek_book_attachments, source: :book
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
  validate :quoted_group_context_must_be_allowed
  validate :group_context_must_not_target_user
  validate :attached_books_must_be_valid

  before_validation :normalize_group_visibility
  before_update :record_content_edited_at
  after_save :refresh_tags!, if: :saved_change_to_content?

  scope :recent, -> { order(created_at: :desc) }
  scope :visible, -> { where(hidden_at: nil) }
  scope :without_profile_conversations, -> { where("jjaeks.target_user_id IS NULL OR jjaeks.target_user_id = jjaeks.user_id") }

  def profile_conversation?
    target_user_id.present? && target_user_id != user_id
  end

  def single_attached_book
    books = attached_books.to_a
    books.first if books.one?
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

  # Authorization (and the Group lock, when applicable) belongs to the caller.
  # Omitted or identically ordered books preserve links and historical markers.
  # [] explicitly clears attachments; nil is invalid.
  def update_attached_books(attributes: {}, books: UNCHANGED_BOOKS)
    if !books.equal?(UNCHANGED_BOOKS) &&
        (!books.is_a?(Array) || books.any? { |book| !book.is_a?(Book) })
      errors.add(:attached_books, :invalid)
      return false
    end

    unless books.equal?(UNCHANGED_BOOKS)
      identities = books.map { |book| book.id || book }
      if identities.uniq.size != identities.size || books.size > MAX_ATTACHED_BOOKS
        errors.add(:attached_books, :invalid)
        return false
      end
    end

    with_lock do
      transaction(requires_new: true) do
        existing_book_ids = attached_books.pluck(:id) unless books.equal?(UNCHANGED_BOOKS)
        unless books.equal?(UNCHANGED_BOOKS) || books.map(&:id) == existing_book_ids
          if requote? && books.any? { |book| book.new_record? || !existing_book_ids.include?(book.id) }
            errors.add(:attached_books, :invalid)
            raise ActiveRecord::RecordInvalid, self
          end
          if requote?
            # Keep historical links (and their IDs/positions); only removal is allowed.
            jjaek_book_attachments.where.not(book_id: books.map(&:id)).delete_all
          else
            jjaek_book_attachments.delete_all
            association(:jjaek_book_attachments).reset
            books.each_with_index do |book, position|
              jjaek_book_attachments.build(book:, position:)
            end
          end
          association(:jjaek_book_attachments).reset if requote?
          association(:attached_books).reset
          if legacy_source_kind == "book" && !jjaek_book_attachments.exists?(visible_on_tombstone: true)
            self.legacy_source_kind = nil
          end
        end
        assign_attributes(attributes)
        save!
      end
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
      quoted_source_kind: legacy_source_kind.presence || "general",
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
    if quoted_jjaek.profile_conversation?
      errors.add(:quoted_jjaek, :invalid) if new_record? || will_save_change_to_quoted_jjaek_id?
      return
    end
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

  def attached_books_must_be_valid
    links = jjaek_book_attachments.reject(&:marked_for_destruction?)
    if links.size > MAX_ATTACHED_BOOKS
      errors.add(:attached_books, :too_many_attachments, count: MAX_ATTACHED_BOOKS)
    end
    books = links.map { |link| link.book_id || link.book }
    errors.add(:attached_books, :taken) if books.uniq.size != books.size

    return unless requote?

    previous_ids = persisted? ? JjaekBookAttachment.where(jjaek_id: id).pluck(:book_id) : []
    if books.any? { |book| !previous_ids.include?(book) }
      errors.add(:attached_books, :invalid)
    end
  end
end
