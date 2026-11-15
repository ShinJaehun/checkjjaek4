require "image_processing/vips"

# Prepare blobs outside the posting transaction so that rollback/crash never
# loses the keys needed for cleanup. Upload, attachment changes and the daily
# ledger commit together. All photo writers use the same PostgreSQL lock.
class JjaekPhotoChanges
  class UnsupportedFormat < StandardError; end

  MAX_SIZE = 5.megabytes
  MAX_PIXELS = 40_000_000
  QUOTA_LOCK = 17_202_611
  LOADERS = %w[jpegload pngload webpload].freeze

  def initialize(files:, remove_ids:)
    @files = files
    @remove_ids = remove_ids
    @prepared = []
  end

  def prepare(jjaek)
    return fail_with(jjaek, :invalid) unless @files.is_a?(Array)
    @files = @files.reject { |file| file == "" }
    return fail_with(jjaek, :limit) if @files.size > Jjaek::MAX_PHOTOS
    return fail_with(jjaek, :no_requote) if jjaek.requote? && @files.any?
    return fail_with(jjaek, :disabled) if @files.any? && !JjaekPhotoUpload.enabled?
    return fail_with(jjaek, :invalid_removal) unless valid_removal_ids?

    @files.each do |file|
      unless file.is_a?(ActionDispatch::Http::UploadedFile) && file.size.positive?
        return fail_with(jjaek, :invalid)
      end
      return fail_with(jjaek, :too_large) if file.size > MAX_SIZE

      optimized = normalize(file)
      return fail_with(jjaek, :too_large) if optimized.size > MAX_SIZE

      blob = ActiveStorage::Blob.build_after_unfurling(
        io: optimized, filename: "photo-#{SecureRandom.hex(12)}.webp", content_type: "image/webp",
        identify: false, metadata: { jjaek_photo: true, analyzed: true },
        service_name: Rails.env.production? ? :oci_photos : Rails.application.config.active_storage.service
      )
      blob.save!
      @prepared << [ blob, optimized ]
      optimized = nil
    ensure
      optimized&.close!
    end
    true
  rescue UnsupportedFormat
    fail_with(jjaek, :unsupported_format)
  rescue Vips::Error, ImageProcessing::Error
    fail_with(jjaek, :invalid)
  end

  def save(jjaek)
    return yield(nil) if @prepared.empty? && @remove_ids.empty?

    saved = false
    Jjaek.transaction(requires_new: true) do
      Jjaek.connection.execute("SELECT pg_advisory_xact_lock(#{QUOTA_LOCK})")
      jjaek.lock! if jjaek.persisted?
      existing = jjaek.ordered_photos.to_a
      removed = existing.select { |photo| @remove_ids.include?(photo.id.to_s) }
      unless removed.size == @remove_ids.size
        fail_with(jjaek, :invalid_removal)
        raise ActiveRecord::Rollback
      end
      if existing.size - removed.size + @prepared.size > Jjaek::MAX_PHOTOS
        fail_with(jjaek, :limit)
        raise ActiveRecord::Rollback
      end

      upload_day = Date.current
      unless quota_available?(jjaek, removed.size, upload_day)
        raise ActiveRecord::Rollback
      end

      @prepared.each do |blob, file|
        file.rewind
        blob.upload_without_unfurling(file)
      end
      removed.each(&:destroy!)
      jjaek.association(:photos_attachments).reset
      jjaek.association(:photos_blobs).reset
      # Assign blobs rather than using attach, which can save a persisted record
      # before the content/books update has been validated.
      blobs = (existing - removed).map(&:blob) + @prepared.map(&:first)
      unless yield(blobs)
        raise ActiveRecord::Rollback
      end
      @prepared.each do |blob, _file|
        JjaekPhotoUpload.create!(user: jjaek.user, blob:, uploaded_on: upload_day, byte_size: blob.byte_size)
      end
      removed_blob_ids = removed.map(&:blob_id)
      ActiveRecord.after_all_transactions_commit do
        removed_blob_ids.each { |id| PurgeJjaekPhotoJob.perform_later(id) }
      end
      saved = true
    end
    unless saved
      jjaek.attachment_changes.delete("photos")
      jjaek.association(:photos_attachments).reset
      jjaek.association(:photos_blobs).reset
    end
    saved
  rescue ActiveStorage::IntegrityError, Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError, IOError, SystemCallError => error
    Rails.logger.warn("Jjaek photo upload failed: #{error.class}")
    fail_with(jjaek, :upload_failed)
  end

  def cleanup
    @prepared.each do |blob, file|
      file.close!
      # Successful attachments survive; failed uploads keep their blob row until
      # purge succeeds, so retries and the storage budget can still see them.
      PurgeJjaekPhotoJob.perform_later(blob.id) unless blob.attachments.exists?
    end
  end

  private

  def valid_removal_ids?
    return false unless @remove_ids.is_a?(Array) && @remove_ids.all? { |id| id.is_a?(String) && id.match?(/\A[1-9]\d*\z/) }

    @remove_ids.uniq.size == @remove_ids.size
  end

  def normalize(file)
    ImageProcessingLock.synchronize do
      unless %w[image/jpeg image/png image/webp].include?(Marcel::MimeType.for(file.tempfile))
        raise UnsupportedFormat
      end
      file.tempfile.rewind
      image = Vips::Image.new_from_file(file.tempfile.path, access: :sequential, fail_on: :warning)
      raise UnsupportedFormat unless LOADERS.include?(image.get("vips-loader"))
      raise Vips::Error, "Unsupported photo" if image.width * image.height > MAX_PIXELS

      ImageProcessing::Vips.source(file.tempfile.path)
        .loader(access: :sequential, fail_on: :warning)
        .resize_to_limit(2000, 2000).convert("webp").saver(strip: true, quality: 85).call
    end
  end

  def quota_available?(jjaek, removed_count, day)
    return true if @prepared.empty?
    return fail_with(jjaek, :disabled) unless JjaekPhotoUpload.enabled?

    daily = JjaekPhotoUpload.where(user_id: jjaek.user_id, uploaded_on: day).count
    return fail_with(jjaek, :daily_limit) if daily + @prepared.size > JjaekPhotoUpload.daily_limit

    retained = ActiveStorage::Attachment.where(record_type: "Jjaek", name: "photos",
      record_id: Jjaek.where(user_id: jjaek.user_id).select(:id)).count
    if retained - removed_count + @prepared.size > JjaekPhotoUpload.retained_limit
      return fail_with(jjaek, :retained_limit)
    end

    # Includes staged and failed blobs until their physical cleanup succeeds.
    if JjaekPhotoUpload.original_blobs.sum(:byte_size) > JjaekPhotoUpload.storage_limit
      return fail_with(jjaek, :storage_limit)
    end
    true
  end

  def fail_with(jjaek, key)
    jjaek.errors.add(:base, :"photo_#{key}", message: I18n.t("jjaek_photos.#{key}"))
    false
  end
end
