require "image_processing/vips"

# One decoder/transformer at a time across web workers on the single beta VM.
# The lock file contains no images and is not persistent image storage.
class ImageProcessingLock
  def self.synchronize
    File.open(Rails.root.join("tmp/image-processing.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      yield
    ensure
      lock.flock(File::LOCK_UN)
    end
  end
end
