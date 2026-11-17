class GroupImagesController < ApplicationController
  include AuthenticatedImageDelivery

  PROFILE_SIZES = { "card" => [ 128, 128 ], "detail" => [ 192, 192 ] }.freeze

  def show
    group = Group.find(params[:group_id])
    raise ActiveRecord::RecordNotFound unless policy(group).view_images?
    authorize group, :view_images?
    attachment = ActiveStorage::Attachment.where(record: group, name: Group::IMAGE_NAMES).find(params[:id])
    original = attachment.blob
    unless original.metadata["group_image"] == true && original.metadata["group_id"] == group.id &&
        original.metadata["group_image_kind"] == attachment.name
      raise ActiveRecord::RecordNotFound
    end
    size = params.fetch(:size, "card")
    dimensions = if attachment.name == "profile_image"
      PROFILE_SIZES[size]
    elsif size == "cover"
      [ 1280, 384 ]
    end
    raise ActiveRecord::RecordNotFound unless dimensions

    blob = ImageProcessingLock.synchronize do
      original.variant(resize_to_fill: dimensions, format: :webp,
        saver: { strip: true, quality: 85 }).processed.image.blob
    end
    group.reload
    unless policy(group).view_images? && ActiveStorage::Attachment.where(record: group, name: Group::IMAGE_NAMES).exists?(attachment.id)
      raise ActiveRecord::RecordNotFound
    end
    send_image_blob(blob)
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    head :not_found
  end
end
