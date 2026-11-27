class BookNoteImage < ApplicationRecord
  STORAGE_LIMIT = 100.megabytes
  MAX_PER_NOTE = 4
  TEMPORARY_LIFETIME = 24.hours

  class AttachmentLimit < StandardError; end

  belongs_to :user
  belongs_to :user_book
  belongs_to :book_note, optional: true
  belongs_to :blob, class_name: "ActiveStorage::Blob"

  enum :state, { uploading: "uploading", temporary: "temporary", attached: "attached", purging: "purging" }, validate: true
  validate :matching_owner_and_note

  scope :purgeable, ->(now = Time.current) {
    detached = where(book_note_id: nil)
    detached.where(state: %w[attached purging])
      .or(detached.where(user_id: nil))
      .or(detached.where(user_book_id: nil))
      .or(detached.temporary.where(expires_at: ..now))
      .or(detached.uploading.where(created_at: ..(now - TEMPORARY_LIFETIME)))
  }

  def temporary_available?
    temporary? && expires_at > Time.current
  end

  # The caller can include this in the transaction that saves the note body.
  def attach_to!(note, user:)
    with_editable_note(note, user) do
      next self if attached? && book_note_id == note.id
      raise ActiveRecord::RecordNotFound unless temporary_available?
      raise AttachmentLimit if note.book_note_images.count >= MAX_PER_NOTE

      update!(book_note: note, state: :attached, expires_at: nil)
      self
    end
  end

  # Removing a reference and saving the note can commit or roll back together.
  def discard_from!(note, user:)
    with_editable_note(note, user) do
      raise ActiveRecord::RecordNotFound unless attached? && book_note_id == note.id

      update!(book_note: nil, state: :purging)
    end
  end

  private

  def with_editable_note(note, user)
    user.with_lock("FOR NO KEY UPDATE") do
      note.with_lock do
        with_lock do
          unless user_book_id == note.user_book_id && BookNoteImagePolicy.new(user, self).create?
            raise ActiveRecord::RecordNotFound
          end

          yield
        end
      end
    end
  end

  def matching_owner_and_note
    errors.add(:user_book, :invalid) if user_book && user_book.user_id != user_id
    errors.add(:book_note, :invalid) if attached? && book_note&.user_book_id != user_book_id
  end
end
