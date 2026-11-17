class CleanupGroupImagesJob < ApplicationJob
  def perform
    # Recover staged uploads left behind by an interrupted request.
    ActiveStorage::Blob.where("metadata::jsonb @> ?", { group_image: true }.to_json)
      .unattached.where(created_at: ...1.day.ago).find_each do |blob|
      PurgeGroupImageJob.perform_later(blob.id)
    end
  end
end
