class BookNoteImagesController < ApplicationController
  include AuthenticatedImageDelivery

  BODY_IMAGE_SIZE = 800

  skip_before_action :authenticate_user!, :reject_suspended_session!, only: :show
  rescue_from ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError,
    ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError, with: -> { head :not_found }

  def create
    image = user_book.book_note_images.build(user: current_user)
    authorize image
    BookNoteImageUpload.new(image:, file: params[:image]).call

    render json: { id: image.id, url: book_book_note_image_path(image.user_book.book_id, image), expires_at: image.expires_at },
      status: :created
  rescue BookNoteImageUpload::Error => error
    status = error.code == :upload_failed ? :service_unavailable : :unprocessable_content
    render json: { error: error.code, message: t("book_note_images.errors.#{error.code}") }, status:
  end

  def show
    return head :not_found unless current_user

    image = user_book.book_note_images.find(params[:id])
    authorize image
    blob = case params.fetch(:size, "original")
    when "original"
      image.blob
    when "body"
      image_variant_blob(image.blob, BODY_IMAGE_SIZE) { verify_image_access!(image) }
    else
      return head :not_found
    end
    return head :not_found unless blob.service.exist?(blob.key)

    verify_image_access!(image)
    send_image_blob(blob)
  end

  private

  def verify_image_access!(image)
    # Ownership or attachment can change while waiting for the transform or storage.
    image.reload
    current_user.reload
    raise ActiveRecord::RecordNotFound unless policy(image).show?
  end

  def user_book
    current_user.user_books.find_by!(book_id: params[:book_id])
  end
end
