class PurgeGroupImageJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: :unlimited

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob && blob.metadata["group_image"] == true

    ImageProcessingLock.synchronize do
      blob.with_lock do
        unless blob.attachments.exists?
          blob.variant_records.includes(image_attachment: :blob).each do |variant|
            variant.image.blob.delete if variant.image.attached?
          end
          blob.delete
          blob.destroy!
        end
      end
    end
  end
end
