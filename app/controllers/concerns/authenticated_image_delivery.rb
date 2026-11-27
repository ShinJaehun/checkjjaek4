module AuthenticatedImageDelivery
  extend ActiveSupport::Concern

  included do
    prepend_before_action :disable_image_caching
  end

  private

  def disable_image_caching
    response.headers["Cache-Control"] = "private, no-store, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Vary"] = "Cookie"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def image_variant_blob(blob, size)
    ImageProcessingLock.synchronize do
      yield if block_given?
      blob.variant(resize_to_limit: [ size, size ], format: :webp,
        saver: { strip: true, quality: 85 }).processed.image.blob
    end
  end

  def send_image_blob(blob)
    response.headers["Content-Type"] = blob.content_type
    response.headers["Content-Length"] = blob.byte_size.to_s
    response.headers["Content-Disposition"] = "inline"
    response.headers["Accept-Ranges"] = "none"
    # No OCI URL redirect, full-file String, or permanent VM copy.
    self.response_body = Enumerator.new do |output|
      blob.download { |chunk| output << chunk }
    end
  end
end
