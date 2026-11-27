require "image_processing/vips"

class BookNoteImageUpload
  MAX_SIZE = 5.megabytes
  MAX_PIXELS = 40_000_000
  MAX_DIMENSION = 1600
  CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  LOADERS = %w[jpegload pngload webpload].freeze

  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end

  def initialize(image:, file:)
    @image = image
    @user = image.user
    @file = file
  end

  def call
    optimized = normalize
    blob = ActiveStorage::Blob.build_after_unfurling(
      io: optimized, filename: "book-note.webp", content_type: "image/webp",
      identify: false, metadata: { book_note_image: true, analyzed: true },
      service_name: Rails.env.production? ? :oci_book_note_images : Rails.application.config.active_storage.service
    )
    reserve!(blob)
    upload!(blob, optimized)
    @image
  rescue Vips::Error, ImageProcessing::Error
    raise Error, :invalid_image
  rescue ActiveStorage::IntegrityError, Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError, IOError, SystemCallError => error
    Rails.logger.warn("Book note image upload failed: #{error.class}")
    raise Error, :upload_failed
  ensure
    optimized&.close!
  end

  private

  def normalize
    unless @file.is_a?(ActionDispatch::Http::UploadedFile) && @file.size.positive?
      raise Error, :invalid_image
    end
    raise Error, :too_large if @file.size > MAX_SIZE

    ImageProcessingLock.synchronize do
      raise Error, :unsupported_format unless CONTENT_TYPES.include?(Marcel::MimeType.for(@file.tempfile))

      @file.rewind
      image = Vips::Image.new_from_file(@file.path, access: :sequential, fail_on: :warning)
      raise Error, :unsupported_format unless LOADERS.include?(image.get("vips-loader"))
      raise Error, :too_many_pixels if image.width * image.height > MAX_PIXELS

      ImageProcessing::Vips.source(@file.path)
        .loader(access: :sequential, fail_on: :warning)
        .resize_to_limit(MAX_DIMENSION, MAX_DIMENSION).convert("webp").saver(strip: true, quality: 85).call
    end
  end

  def reserve!(blob)
    # Commit the key and byte reservation before sending any bytes to storage.
    @user.with_lock("FOR NO KEY UPDATE") do
      raise ActiveRecord::RecordNotFound unless BookNoteImagePolicy.new(@user, @image).create?

      bytes = BookNoteImage.where(user: @user).joins(:blob).sum("active_storage_blobs.byte_size")
      raise Error, :storage_limit if bytes + blob.byte_size > BookNoteImage::STORAGE_LIMIT

      blob.save!
      @image.blob = blob
      @image.save!
    end
  end

  def upload!(blob, optimized)
    @user.with_lock("FOR NO KEY UPDATE") do
      @image.with_lock do
        unless @image.uploading? && BookNoteImagePolicy.new(@user, @image).create?
          raise ActiveRecord::RecordNotFound
        end

        optimized.rewind
        blob.upload_without_unfurling(optimized)
        @image.update!(state: :temporary, expires_at: BookNoteImage::TEMPORARY_LIFETIME.from_now)
      end
    end
  rescue StandardError
    # Cleanup also finds abandoned reservations if the process stops before this runs.
    BookNoteImage.uploading.where(id: @image.id).update_all(state: :purging, updated_at: Time.current)
    raise
  end
end
