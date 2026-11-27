class PurgeBookNoteImageJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: :unlimited

  def perform(image_id)
    ImageProcessingLock.synchronize do
      BookNoteImage.transaction do
        image = BookNoteImage.purgeable.lock.find_by(id: image_id)
        next unless image

        blob = image.blob
        if blob.attachments.exists?
          raise ActiveRecord::RecordNotDestroyed, "Book note image blob has an unexpected attachment"
        end

        # Keep the reservation and keys until every object deletion succeeds.
        blob.variant_records.includes(image_attachment: :blob).each do |record|
          variant_blob = record.image.blob
          variant_blob.service.delete(variant_blob.key) if variant_blob
        end
        blob.service.delete(blob.key)
        image.destroy!
        blob.destroy!
      end
    end
  end
end
