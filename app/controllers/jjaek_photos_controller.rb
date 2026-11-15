class JjaekPhotosController < ApplicationController
  include AuthenticatedImageDelivery

  SIZES = { "card" => 800, "gallery" => 1600 }.freeze

  def show
    jjaek = Jjaek.find(params[:jjaek_id])
    raise ActiveRecord::RecordNotFound unless policy(jjaek).view_photos?
    authorize jjaek, :view_photos?
    attachment = jjaek.photos_attachments.find(params[:id])
    size = params.fetch(:size, "card")
    raise ActiveRecord::RecordNotFound unless SIZES.key?(size) || size == "original"

    blob = if size == "original"
      attachment.blob
    else
      ImageProcessingLock.synchronize do
        attachment.blob.variant(resize_to_limit: [ SIZES.fetch(size), SIZES.fetch(size) ],
          format: :webp, saver: { strip: true, quality: 85 }).processed.image.blob
      end
    end
    # Recheck after the transform lock: queued requests must see changed policy.
    jjaek.reload
    raise ActiveRecord::RecordNotFound unless policy(jjaek).view_photos? && jjaek.photos_attachments.exists?(attachment.id)

    send_image_blob(blob)
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    head :not_found
  end
end
