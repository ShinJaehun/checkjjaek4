class PurgeBookNoteImageJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: :unlimited

  def perform(image_id)
    BookNoteImage.transaction do
      image = BookNoteImage.purgeable.lock.find_by(id: image_id)
      next unless image

      blob = image.blob
      if blob.attachments.exists?
        raise ActiveRecord::RecordNotDestroyed, "Book note image blob has an unexpected attachment"
      end

      # Keep the reservation and the storage key until object deletion succeeds.
      blob.service.delete(blob.key)
      image.destroy!
      blob.destroy!
    end
  end
end
