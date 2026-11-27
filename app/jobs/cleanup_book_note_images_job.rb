class CleanupBookNoteImagesJob < ApplicationJob
  def perform
    BookNoteImage.purgeable.find_each do |image|
      PurgeBookNoteImageJob.perform_later(image.id)
    end
  end
end
