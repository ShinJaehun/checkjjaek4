class CleanupJjaekPhotosJob < ApplicationJob
  def perform
    # Reclaims uploads interrupted by process death as well as missed enqueueing.
    JjaekPhotoUpload.original_blobs.unattached.where(created_at: ...1.day.ago).find_each do |blob|
      PurgeJjaekPhotoJob.perform_later(blob.id)
    end
  end
end
