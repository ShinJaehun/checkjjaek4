class UserAvatarsController < ApplicationController
  include AuthenticatedImageDelivery

  def show
    user = User.find_by_public_param!(params[:user_id])
    size = params.fetch(:size, "128")
    raise ActiveRecord::RecordNotFound unless %w[128 512].include?(size) && !user.withdrawn? && user.avatar.attached?
    original = user.avatar.blob
    if original.metadata["jjaek_photo"] || original.metadata["group_image"] || original.attachments.where(record_type: "ActiveStorage::VariantRecord").exists?
      raise ActiveRecord::RecordNotFound
    end

    blob = ImageProcessingLock.synchronize do
      user.avatar.variant(resize_to_fill: [ size.to_i, size.to_i ]).processed.image.blob
    end
    send_image_blob(blob)
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    head :not_found
  end
end
