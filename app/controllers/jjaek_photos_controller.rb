class JjaekPhotosController < ApplicationController
  include AuthenticatedImageDelivery

  SIZES = { "card" => 640, "gallery" => 1600 }.freeze

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
      image_variant_blob(attachment.blob, SIZES.fetch(size))
    end
    # Recheck after the transform lock: queued requests must see changed policy.
    jjaek.reload
    current_user.reload
    return head :not_found unless policy(jjaek).view_photos? && jjaek.photos_attachments.exists?(attachment.id)

    send_image_blob(blob)
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    head :not_found
  end
end
