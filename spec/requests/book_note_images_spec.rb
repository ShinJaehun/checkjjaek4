require "rails_helper"

RSpec.describe "Book note images", type: :request do
  let(:owner) { User.create!(name: "Reader", email: "note-images@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Book with private images") }
  let!(:entry) { owner.bookshelf_entries.create!(book:) }

  def upload_image(file = Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"))
    post book_book_note_images_path(book), params: { image: Rack::Test::UploadedFile.new(file, "application/octet-stream") },
      headers: { "Accept" => "application/json" }
  end

  after do
    BookNoteImage.where(user: owner).includes(:blob).find_each { |image| image.blob.service.delete(image.blob.key) }
  end

  it "stores an optimized private image and streams it only to its owner" do
    sign_in owner
    Tempfile.create([ "note-image", ".jpeg" ]) do |file|
      original = Vips::Image.black(2400, 1200).copy
      original.set_type(GObject::GSTR_TYPE, "exif-ifd0-Artist", "PRIVATE_CAMERA_NAME")
      original.write_to_file(file.path)
      upload_image(file.path)
    end

    expect(response).to have_http_status(:created)
    image = entry.user_book.book_note_images.sole
    path = book_book_note_image_path(book, image)
    expect(response.parsed_body.keys).to match_array(%w[id url expires_at])
    expect(response.parsed_body).to include("id" => image.id, "url" => path)
    expect(image).to be_temporary
    expect(image.expires_at).to be_within(5.seconds).of(24.hours.from_now)
    expect(image.blob.content_type).to eq("image/webp")
    image.blob.open do |file|
      stored = Vips::Image.new_from_file(file.path)
      expect([ stored.width, stored.height ]).to eq([ 1600, 800 ])
      expect(stored.get_fields.grep(/exif|gps/i)).to be_empty
    end

    get path
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/webp")
    expect(response.headers["Cache-Control"]).to include("private", "no-store")
    expect(response.body.b).to eq(image.blob.download)

    sign_out owner
    get path
    expect(response).to have_http_status(:not_found)

    [ false, true ].each do |admin|
      other = User.create!(name: "Other", email: "note-image-viewer-#{admin}@example.com", password: "password123!", global_admin: admin)
      other.bookshelf_entries.create!(book:)
      sign_in other
      get path
      expect(response).to have_http_status(:not_found)
      sign_out other
    end

    sign_in owner
    image.update!(expires_at: 1.second.ago)
    get path
    expect(response).to have_http_status(:not_found)

    image.update!(expires_at: 24.hours.from_now)
    image.blob.service.delete(image.blob.key)
    get path
    expect(response).to have_http_status(:not_found)
  end

  it "rejects unsupported, corrupted, and oversized uploads before reserving storage" do
    sign_in owner
    Tempfile.create([ "note-image", ".png" ]) do |file|
      file.binmode
      file.write('<svg xmlns="http://www.w3.org/2000/svg"/>')
      file.flush
      upload_image(file.path)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("unsupported_format")

      file.rewind
      file.write("\x89PNG\r\n\x1A\n".b)
      file.truncate(file.pos)
      file.flush
      upload_image(file.path)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("invalid_image")

      file.truncate(5.megabytes + 1)
      upload_image(file.path)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("too_large")
    end
    expect(entry.user_book.book_note_images).to be_empty
  end

  it "blocks uploads for missing or removed placements while keeping existing images readable" do
    sign_in owner
    upload_image
    image = entry.user_book.book_note_images.sole
    note = entry.user_book.book_notes.create!(body: "Private note")
    image.attach_to!(note, user: owner)
    path = book_book_note_image_path(book, image)

    other = User.create!(name: "Other", email: "note-image-upload-viewer@example.com", password: "password123!")
    sign_in other
    upload_image
    expect(response).to have_http_status(:not_found)
    sign_out other

    sign_in owner
    delete bookshelf_entry_path(entry)
    expect(response).to have_http_status(:see_other)
    upload_image
    expect(response).to have_http_status(:not_found)
    get path
    expect(response).to have_http_status(:ok)

    owner.bookshelf_entries.create!(book:)
    delete book_book_note_path(book, note)
    expect(response).to have_http_status(:see_other)
    get path
    expect(response).to have_http_status(:not_found)
    expect(image.reload.book_note_id).to be_nil
    expect(BookNoteImage.purgeable).to include(image)
  end

  it "counts temporary images toward the member's storage limit" do
    sign_in owner
    upload_image
    image = entry.user_book.book_note_images.sole
    stub_const("BookNoteImage::STORAGE_LIMIT", image.blob.byte_size)

    expect { upload_image }.not_to change(ActiveStorage::Blob, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to include("error" => "storage_limit", "message" => I18n.t("book_note_images.errors.storage_limit"))
  end

  it "keeps a failed write tracked for cleanup and denies its use" do
    sign_in owner
    allow(ActiveStorage::Blob.service).to receive(:upload).and_wrap_original do |upload, *args, **kwargs|
      upload.call(*args, **kwargs)
      raise IOError, "Storage interrupted"
    end

    upload_image
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["error"]).to eq("upload_failed")
    image = entry.user_book.book_note_images.sole
    expect(image).to be_purging
    expect(BookNoteImage.purgeable).to include(image)
    get book_book_note_image_path(book, image)
    expect(response).to have_http_status(:not_found)
  end
end
