require "image_processing/vips"

# Only uploaded files enter this path; signed blob IDs cannot reuse private images.
class GroupImageChanges
  def initialize(parameters)
    @parameters = parameters
    @prepared = {}
  end

  def prepare(group)
    Group::IMAGE_NAMES.each do |name|
      file = @parameters["#{name}_file"]
      next if file == "" || file.nil?

      unless file.is_a?(ActionDispatch::Http::UploadedFile) && file.size.positive?
        return fail_with(group, name, :invalid_format)
      end
      return fail_with(group, name, :too_large) if file.size > Group::MAX_IMAGE_SIZE

      optimized = normalize(file, name)
      return fail_with(group, name, :too_large) if optimized.size > Group::MAX_IMAGE_SIZE

      blob = ActiveStorage::Blob.build_after_unfurling(
        io: optimized, filename: "group-#{SecureRandom.hex(12)}.webp", content_type: "image/webp",
        identify: false, metadata: { group_image: true, group_id: group.id, group_image_kind: name, analyzed: true },
        service_name: Rails.env.production? ? :oci_photos : Rails.application.config.active_storage.service
      )
      # Persist the cleanup key before uploading, including partially failed uploads.
      blob.save!
      @prepared[name] = blob
      optimized.rewind
      blob.upload_without_unfurling(optimized)
    rescue Vips::Error, ImageProcessing::Error
      return fail_with(group, name, :invalid_format)
    rescue ActiveStorage::IntegrityError, Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError, IOError, SystemCallError => error
      Rails.logger.warn("Group image upload failed: #{error.class}")
      return fail_with(group, name, :upload_failed)
    ensure
      optimized&.close!
      optimized = nil
    end
    true
  end

  # Called inside the Group row lock, after authorization has been rechecked.
  def save(group)
    attachments = {}
    Group::IMAGE_NAMES.each do |name|
      if @prepared.key?(name)
        attachments[name] = @prepared.fetch(name)
      elsif ActiveModel::Type::Boolean.new.cast(@parameters["remove_#{name}"])
        attachments[name] = nil
      end
    end
    old_blob_ids = attachments.keys.filter_map { |name| group.public_send("#{name}_attachment")&.blob_id }
    saved = yield(attachments)
    if saved
      ActiveRecord.after_all_transactions_commit do
        old_blob_ids.each { |id| PurgeGroupImageJob.perform_later(id) }
      end
    else
      attachments.each_key do |name|
        group.attachment_changes.delete(name)
        group.association("#{name}_attachment".to_sym).reset
        group.association("#{name}_blob".to_sym).reset
      end
    end
    saved
  end

  def cleanup
    @prepared.each_value do |blob|
      PurgeGroupImageJob.perform_later(blob.id) unless blob.attachments.exists?
    end
  end

  private

  def normalize(file, name)
    ImageProcessingLock.synchronize do
      unless %w[image/jpeg image/png image/webp].include?(Marcel::MimeType.for(file.tempfile))
        raise Vips::Error, "Unsupported group image"
      end
      file.tempfile.rewind
      image = Vips::Image.new_from_file(file.tempfile.path, access: :sequential, fail_on: :warning)
      unless %w[jpegload pngload webpload].include?(image.get("vips-loader")) && image.width * image.height <= 40_000_000
        raise Vips::Error, "Unsupported group image"
      end
      limit = name == "profile_image" ? 512 : 1600
      ImageProcessing::Vips.source(file.tempfile.path)
        .loader(access: :sequential, fail_on: :warning)
        .resize_to_limit(limit, limit).convert("webp").saver(strip: true, quality: 85).call
    end
  end

  def fail_with(group, name, key)
    group.errors.add(name, key, message: I18n.t("groups.branding.#{key}"))
    false
  end
end
