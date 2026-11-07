class JjaekBookAttachment < ApplicationRecord
  belongs_to :jjaek, inverse_of: :jjaek_book_attachments
  belongs_to :book

  validates :book_id, uniqueness: { scope: :jjaek_id }, if: -> { book_id.present? }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       uniqueness: { scope: :jjaek_id }
  validate :attachment_context_must_be_valid

  private

  def attachment_context_must_be_valid
    return unless jjaek

    if (new_record? || will_save_change_to_book_id?) && jjaek.requote?
      errors.add(:jjaek, :invalid)
    end
    if new_record? && jjaek.persisted? &&
        jjaek.jjaek_book_attachments.count >= Jjaek::MAX_ATTACHED_BOOKS
      errors.add(:jjaek, :invalid)
    end
  end
end
