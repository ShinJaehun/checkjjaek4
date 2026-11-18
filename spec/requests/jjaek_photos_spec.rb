require "rails_helper"

RSpec.describe "Jjaek photos", type: :request do
  let(:writer) { User.create!(name: "Photo writer", email: "photos-writer@example.com", password: "password123!") }
  let(:reader) { User.create!(name: "Photo reader", email: "photos-reader@example.com", password: "password123!") }

  def photo_upload
    Rack::Test::UploadedFile.new(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"), "image/png")
  end

  def create_photo_post(**attributes)
    sign_in writer
    post jjaeks_path, params: { jjaek: { content: "Photo #reading", photo_files: [ photo_upload ], **attributes } }
    expect(response).to have_http_status(:see_other)
    writer.jjaeks.order(:id).last
  end

  def expect_photo_access(jjaek, photo, status)
    %w[original card gallery].each do |size|
      get jjaek_photo_path(jjaek, photo, size:)
      expect(response).to have_http_status(status)
      if status == :ok
        expect(response.media_type).to eq("image/webp")
        expect(response.headers["Cache-Control"]).to include("private", "no-store")
        expect(response.headers["Location"]).to be_nil
        expect(response.body).to start_with("RIFF")
      end
    end
  end

  before do
    allow(JjaekPhotoUpload).to receive_messages(enabled?: true, daily_limit: 4, retained_limit: 50, storage_limit: 1.gigabyte)
  end

  after do
    JjaekPhotoUpload.original_blobs.find_each do |blob|
      blob.variant_records.each { |variant| variant.image.blob.delete if variant.image.attached? }
      blob.delete
    end
  end

  [ 0, 1, 4 ].each do |count|
    it "creates a required-body Jjaek with #{count} photos and five independent books" do
      sign_in writer
      books = 5.times.map { |index| Book.create!(title: "Photo book #{index}") }
      expect {
        post jjaeks_path, params: {
          selected_books: books.map(&:id),
          jjaek: { content: "Books and photos #reading", photo_files: Array.new(count) { photo_upload } }
        }
      }.to change(JjaekPhotoUpload, :count).by(count)
      expect(response).to have_http_status(:see_other)
      saved = writer.jjaeks.last
      expect(saved.photos.count).to eq(count)
      expect(saved.attached_books).to eq(books)
      expect(saved.tags.pluck(:name)).to eq([ "reading" ])
      expect(writer.bookshelf_entries).to be_empty
      get jjaek_path(saved)
      expect(response.body).to include("Books and photos")
      expect(Nokogiri::HTML(response.body).css(".jjaek-photo-grid button").size).to eq(count)
    end
  end

  it "acknowledges composer saves directly after creating and updating the Jjaek" do
    sign_in writer
    headers = { "X-Jjaek-Composer" => "true", "ACCEPT" => "text/vnd.turbo-stream.html, text/html" }
    post jjaeks_path, params: { selected_books: [ Book.create!(title: "Acknowledged book").id ],
      jjaek: { content: "Acknowledged", photo_files: [ photo_upload ] } }, headers: headers

    saved = writer.jjaeks.last
    expect(response).to have_http_status(:no_content)
    expect(response.headers["X-Jjaek-Saved-Location"]).to eq(jjaek_path(saved))
    expect(saved.content).to eq("Acknowledged")
    expect(saved.photos.count).to eq(1)
    expect(saved.attached_books.pluck(:title)).to eq([ "Acknowledged book" ])
    get response.headers.fetch("X-Jjaek-Saved-Location")
    expect(response.body).to include(I18n.t("jjaeks.notices.created"))

    patch jjaek_path(saved), params: { jjaek: { content: "Acknowledged edit", remove_photo_ids: [ saved.photos.first.id ] } }, headers: headers
    expect(response).to have_http_status(:no_content)
    expect(response.headers["X-Jjaek-Saved-Location"]).to eq(jjaek_path(saved))
    expect(saved.reload.content).to eq("Acknowledged edit")
    expect(saved.photos).not_to be_attached
    get response.headers.fetch("X-Jjaek-Saved-Location")
    expect(response.body).to include(I18n.t("jjaeks.notices.updated"))
  end

  it "does not acknowledge an unauthenticated composer redirect, even when its destination returns 200" do
    expect {
      post jjaeks_path, params: { jjaek: { content: "Expired session", photo_files: [ photo_upload ] } },
        headers: { "X-Jjaek-Composer" => "true", "ACCEPT" => "text/vnd.turbo-stream.html, text/html" }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(new_user_session_path)
    expect(response.headers["X-Jjaek-Saved-Location"]).to be_nil
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Jjaek-Saved-Location"]).to be_nil
    expect(response.body).not_to include(I18n.t("jjaeks.notices.created"))
  end

  it "edits, appends in order and individually removes photos without changing books" do
    jjaek = create_photo_post
    first = jjaek.ordered_photos.first
    patch jjaek_path(jjaek), params: { jjaek: { content: "Edited", photo_files: [ photo_upload, photo_upload ] } }
    expect(response).to have_http_status(:see_other)
    ids = jjaek.reload.ordered_photos.map(&:id)
    expect(ids.size).to eq(3)
    expect(ids.first).to eq(first.id)
    patch jjaek_path(jjaek), params: { jjaek: { content: "Removed one", remove_photo_ids: [ ids.second.to_s ] } }
    expect(response).to have_http_status(:see_other)
    expect(jjaek.reload.ordered_photos.map(&:id)).to eq([ ids.first, ids.third ])
    expect(JjaekPhotoUpload.where(user: writer).count).to eq(3)
    get edit_jjaek_path(jjaek)
    expect(Nokogiri::HTML(response.body).css("[data-photo-id]").map { |node| node["data-photo-id"].to_i }).to eq([ ids.first, ids.third ])
  end

  it "handles photo parameters separately in create and update while still reporting forbidden attributes" do
    sign_in writer
    allow(ActionController::Parameters).to receive(:action_on_unpermitted_parameters).and_return(:log)
    unpermitted = []
    subscriber = ->(_name, _start, _finish, _id, payload) { unpermitted.concat(payload.fetch(:keys)) }

    ActiveSupport::Notifications.subscribed(subscriber, "unpermitted_parameters.action_controller") do
      post jjaeks_path, params: { jjaek: { content: "Created", photo_files: [ photo_upload ], user_id: reader.id } }
      expect(response).to have_http_status(:see_other)
      jjaek = writer.jjaeks.last
      photo = jjaek.ordered_photos.first

      patch jjaek_path(jjaek), params: { jjaek: {
        content: "Updated", photo_files: [ photo_upload ], remove_photo_ids: [ photo.id.to_s ], user_id: reader.id
      } }
      expect(response).to have_http_status(:see_other)
      expect(jjaek.reload).to have_attributes(user_id: writer.id, content: "Updated")
      expect(jjaek.photos.count).to eq(1)
      expect(jjaek.ordered_photos.first.id).not_to eq(photo.id)
    end

    expect(unpermitted).not_to include("photo_files", "remove_photo_ids")
    expect(unpermitted).to include("user_id")
  end

  it "rejects more than four, a missing body, broken images and signed blob IDs without consuming the daily quota" do
    sign_in writer
    attempts = [
      { content: "Too many", photo_files: Array.new(5) { photo_upload } },
      { content: "", photo_files: [ photo_upload ] },
      { content: "Spoofed attachment", photo_files: [ "signed-blob-id" ] }
    ]
    Tempfile.create([ "broken-photo", ".png" ]) do |file|
      file.write("not an image")
      file.flush
      attempts << { content: "Invalid", photo_files: [ Rack::Test::UploadedFile.new(file.path, "image/png") ] }
      attempts.each do |attributes|
        expect {
          post jjaeks_path, params: { jjaek: attributes }, headers: { "X-Jjaek-Composer" => "true" }
        }.not_to change(Jjaek, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.headers["X-Jjaek-Saved-Location"]).to be_nil
      end
    end
    expect(JjaekPhotoUpload.where(user: writer)).to be_empty
    JjaekPhotoUpload.original_blobs.unattached.each do |blob|
      key = blob.key
      service = blob.service
      PurgeJjaekPhotoJob.perform_now(blob.id)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
      expect(service.exist?(key)).to be(false)
    end
  end

  it "edits four photos without recharging the full daily quota and can remove all four" do
    sign_in writer
    post jjaeks_path, params: { jjaek: { content: "Four", photo_files: Array.new(4) { photo_upload } } }
    jjaek = writer.jjaeks.last
    ids = jjaek.ordered_photos.map { |photo| photo.id.to_s }
    patch jjaek_path(jjaek), params: { jjaek: { content: "Same four" } }
    expect(response).to have_http_status(:see_other)
    expect(jjaek.reload.photos.count).to eq(4)
    patch jjaek_path(jjaek), params: { jjaek: { content: "Now zero", remove_photo_ids: ids } }
    expect(response).to have_http_status(:see_other)
    expect(jjaek.reload.photos).not_to be_attached
    expect(JjaekPhotoUpload.where(user: writer).count).to eq(4)
  end

  it "cannot remove an attachment belonging to a different parent" do
    first = create_photo_post
    second = create_photo_post
    foreign_id = second.ordered_photos.first.id
    patch jjaek_path(first), params: { jjaek: { content: "Attack", remove_photo_ids: [ foreign_id.to_s ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(first.reload.content).to eq("Photo #reading")
    expect(first.photos.count).to eq(1)
    expect(second.reload.photos.count).to eq(1)
  end

  it "keeps content, tags, books, visibility and previous files when an edit fails" do
    jjaek = create_photo_post(visibility: :private_jjaek)
    photo = jjaek.ordered_photos.first
    book = Book.create!(title: "Must roll back")
    patch jjaek_path(jjaek), params: { selected_books: [ book.id ],
      jjaek: { content: "", visibility: :public_jjaek, remove_photo_ids: [ photo.id.to_s ], photo_files: [ photo_upload ] } },
      headers: { "X-Jjaek-Composer" => "true" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.headers["X-Jjaek-Saved-Location"]).to be_nil
    expect(jjaek.reload).to have_attributes(content: "Photo #reading", visibility: "private_jjaek")
    expect(jjaek.ordered_photos.map(&:id)).to eq([ photo.id ])
    expect(jjaek.tags.pluck(:name)).to eq([ "reading" ])
    expect(jjaek.attached_books).to be_empty
    expect(JjaekPhotoUpload.where(user: writer).count).to eq(1)
    expect(photo.blob.service.exist?(photo.blob.key)).to be(true)
  end

  it "does not reset a day's quota after deletion, and allows text edits while uploads are paused" do
    sign_in writer
    post jjaeks_path, params: { jjaek: { content: "Four", photo_files: Array.new(4) { photo_upload } } }
    jjaek = writer.jjaeks.last
    delete jjaek_path(jjaek)
    expect(JjaekPhotoUpload.where(user: writer).count).to eq(4)
    expect { post jjaeks_path, params: { jjaek: { content: "Fifth", photo_files: [ photo_upload ] } } }.not_to change(Jjaek, :count)
    expect(response.body).to include(I18n.t("jjaek_photos.daily_limit"))
    plain = writer.jjaeks.create!(content: "No photos")
    allow(JjaekPhotoUpload).to receive(:enabled?).and_return(false)
    patch jjaek_path(plain), params: { jjaek: { content: "Still editable" } }
    expect(response).to have_http_status(:see_other)
    post jjaeks_path, params: { jjaek: { content: "Paused", photo_files: [ photo_upload ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("jjaek_photos.disabled"))
  end

  it "enforces retained and service byte budgets before uploading" do
    jjaek = create_photo_post
    allow(JjaekPhotoUpload).to receive(:retained_limit).and_return(1)
    post jjaeks_path, params: { jjaek: { content: "Over retained", photo_files: [ photo_upload ] } }
    expect(response.body).to include(I18n.t("jjaek_photos.retained_limit"))
    allow(JjaekPhotoUpload).to receive(:retained_limit).and_return(50)
    allow(JjaekPhotoUpload).to receive(:storage_limit).and_return(jjaek.photos.blobs.sum(:byte_size))
    post jjaeks_path, params: { jjaek: { content: "Over bytes", photo_files: [ photo_upload ] } }
    expect(response.body).to include(I18n.t("jjaek_photos.storage_limit"))
    expect(JjaekPhotoUpload.where(user: writer).count).to eq(1)
  end

  %i[daily_limit retained_limit storage_limit].each do |limit|
    it "renders #{limit} in the inline photo alert without duplicating the body error" do
      sign_in writer
      allow(JjaekPhotoUpload).to receive(limit).and_return(0)
      post jjaeks_path, params: { jjaek: { content: "Keep this body", photo_files: [ photo_upload ] } }
      expect(response).to have_http_status(:unprocessable_content)
      document = Nokogiri::HTML(response.body)
      photo_alert = document.at_css("[data-jjaek-photos-target='error'][role='alert']")
      expect(photo_alert["hidden"]).to be_nil
      expect(photo_alert.at_css("[data-photo-error-code='#{limit}']").text).to eq(I18n.t("jjaek_photos.#{limit}"))
      expect(document.at_css("[data-content-length-target='serverErrors']").text.strip).to eq("")
      expect(document.at_css("textarea[name='jjaek[content]']").text.strip).to eq("Keep this body")
      expect(writer.jjaeks).to be_empty
    end
  end

  it "shows an upload failure in the photo alert while preserving the body" do
    sign_in writer
    allow_any_instance_of(ActiveStorage::Blob).to receive(:upload_without_unfurling).and_raise(IOError, "Interrupted")
    post jjaeks_path, params: { jjaek: { content: "Keep this body", photo_files: [ photo_upload ] } }
    expect(response).to have_http_status(:unprocessable_content)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-jjaek-photos-target='error'][role='alert'] [data-photo-error-code='upload_failed']").text)
      .to eq(I18n.t("jjaek_photos.upload_failed"))
    expect(document.at_css("[data-content-length-target='serverErrors']").text.strip).to eq("")
    expect(document.at_css("textarea[name='jjaek[content]']").text.strip).to eq("Keep this body")
    expect(writer.jjaeks).to be_empty
  end

  it "denies guests, wrong parents, strangers and stale URLs after visibility changes" do
    jjaek = create_photo_post
    photo = jjaek.ordered_photos.first
    sign_out writer
    get jjaek_photo_path(jjaek, photo)
    expect(response).to redirect_to(new_user_session_path)
    sign_in reader
    expect_photo_access(jjaek, photo, :ok)
    other = reader.jjaeks.create!(content: "Other parent")
    expect_photo_access(other, photo, :not_found)
    jjaek.update!(visibility: :private_jjaek)
    expect_photo_access(jjaek, photo, :not_found)
    sign_in writer
    expect_photo_access(jjaek, photo, :ok)
  end

  it "checks book friendship on each request, including already generated variants" do
    friendship = BookFriendship.create!(requester: writer, addressee: reader, status: :accepted)
    jjaek = create_photo_post(visibility: :book_friends)
    photo = jjaek.ordered_photos.first
    sign_in reader
    expect_photo_access(jjaek, photo, :ok)
    friendship.destroy!
    expect_photo_access(jjaek, photo, :not_found)
  end

  it "does not deliver a variant when the viewer is suspended during processing" do
    BookFriendship.create!(requester: writer, addressee: reader, status: :accepted)
    jjaek = create_photo_post(visibility: :book_friends)
    photo = jjaek.ordered_photos.first
    sign_in reader
    allow(ImageProcessingLock).to receive(:synchronize).and_wrap_original do |original, &process|
      original.call(&process).tap { User.where(id: reader.id).update_all(suspended_at: Time.current) }
    end

    get jjaek_photo_path(jjaek, photo, size: "card")

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).not_to eq("image/webp")
    expect(response.headers["Cache-Control"]).to include("private", "no-store")
  end

  it "keeps a profile conversation exclusive to its two participants after friendship ends" do
    friendship = BookFriendship.create!(
      requester: writer,
      addressee: reader,
      status: :accepted
    )
    jjaek = create_photo_post(target_user_id: reader.id, visibility: :public_jjaek)
    photo = jjaek.ordered_photos.first

    expect(jjaek).to be_profile_conversation

    friendship.destroy!

    # 실제 HTTP 세션에서 reader로 로그인
    delete destroy_user_session_path
    post user_session_path, params: {
      user: { email: reader.email, password: "password123!" }
    }
    expect(response).to redirect_to(root_path)
    expect_photo_access(jjaek, photo, :ok)

    # 실제 HTTP 세션에서 제3자로 전환
    third = User.create!(
      name: "Third",
      email: "photo-third@example.com",
      password: "password123!"
    )

    delete destroy_user_session_path
    post user_session_path, params: {
      user: { email: third.email, password: "password123!" }
    }
    expect(response).to redirect_to(root_path)

    expect(JjaekPolicy.new(third, jjaek).view_photos?).to be(false)
    expect_photo_access(jjaek, photo, :not_found)
  end

  it "rechecks private Group membership and hides moderated content from other readers" do
    group = Group.create!(name: "Photo group", group_admin: writer, group_type: :private_group, lifecycle_status: :active)
    membership = group.group_memberships.create!(user: reader, status: :active)
    sign_in writer
    post group_jjaeks_path(group), params: { jjaek: { content: "Group photos", photo_files: [ photo_upload ] } }
    jjaek = group.jjaeks.last
    photo = jjaek.ordered_photos.first
    sign_in reader
    expect_photo_access(jjaek, photo, :ok)
    jjaek.update_columns(hidden_at: Time.current)
    expect_photo_access(jjaek, photo, :not_found)
    jjaek.update_columns(hidden_at: nil)
    membership.destroy!
    expect_photo_access(jjaek, photo, :not_found)
  end

  it "removes files on hard deletion and tombstoning, preserving comments and daily history" do
    [ false, true ].each do |with_comment|
      jjaek = create_photo_post
      jjaek.comments.create!(user: reader, content: "Preserve me") if with_comment
      photo = jjaek.ordered_photos.first
      blob = photo.blob
      delete jjaek_path(jjaek)
      expect(ActiveStorage::Attachment.exists?(photo.id)).to be(false)
      expect_photo_access(jjaek, photo, :not_found)
      PurgeJjaekPhotoJob.perform_now(blob.id)
      expect(blob.service.exist?(blob.key)).to be(false)
      if with_comment
        expect(jjaek.reload).to be_deleted
        expect(jjaek.comments.count).to eq(1)
      end
    end
    expect(JjaekPhotoUpload.where(user: writer).count).to eq(2)
  end

  it "shows source photos on requotes only while the source is accessible and rejects new requote photos" do
    source = create_photo_post
    sign_in reader
    quote = reader.jjaeks.create!(content: "My quote", quoted_jjaek: source)
    get jjaek_path(quote)
    expect(response.body).to include(jjaek_photo_path(source, source.ordered_photos.first, size: :card).gsub("&", "&amp;"))
    patch jjaek_path(quote), params: { jjaek: { content: "My quote", photo_files: [ photo_upload ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(quote.reload.photos).not_to be_attached
    source.update!(visibility: :private_jjaek)
    expect_photo_access(source, source.ordered_photos.first, :not_found)
  end

  it "closes default Active Storage original, variant, Disk and direct-upload routes" do
    jjaek = create_photo_post(visibility: :private_jjaek)
    blob = jjaek.photos.blobs.first
    variant_key = blob.variant(resize_to_limit: [ 800, 800 ]).variation.key
    [ "/rails/active_storage/blobs/redirect/#{blob.signed_id}/photo.webp",
      "/rails/active_storage/blobs/proxy/#{blob.signed_id}/photo.webp",
      "/rails/active_storage/representations/redirect/#{blob.signed_id}/#{variant_key}/photo.webp",
      "/rails/active_storage/representations/proxy/#{blob.signed_id}/#{variant_key}/photo.webp",
      "/rails/active_storage/disk/encoded-key/photo.webp" ].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    post "/rails/active_storage/direct_uploads", params: { blob: { filename: "photo.webp" } }
    expect(response).to have_http_status(:not_found)
  end

  it "cannot attach a private photo or its variant as an avatar using a signed blob reference" do
    jjaek = create_photo_post(visibility: :private_jjaek)
    blob = jjaek.photos.blobs.first
    variant = ImageProcessingLock.synchronize { blob.variant(resize_to_limit: [ 800, 800 ]).processed.image.blob }
    sign_in reader
    [ blob, variant ].each do |image|
      patch avatar_account_settings_path, params: { user: { avatar: image.signed_id } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(reader.reload.avatar).not_to be_attached
      get user_avatar_image_path(reader, size: 128)
      expect(response).to have_http_status(:not_found)
    end
    expect(jjaek.reload.photos.count).to eq(1)
    expect_photo_access(jjaek, jjaek.ordered_photos.first, :not_found)
  end

  it "delivers uploaded avatars in both existing sizes through authenticated routes" do
    writer.update!(handle: "photo_avatar")
    File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png")) do |file|
      writer.avatar.attach(io: file, filename: "avatar.png", content_type: "image/png")
    end
    sign_in reader
    [ 128, 512 ].each do |size|
      get user_avatar_image_path(writer, size:)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      decoded = Vips::Image.new_from_buffer(response.body, "")
      expect([ decoded.width, decoded.height ]).to eq([ size, size ])
    end
    get user_avatar_image_path(writer, size: "original")
    expect(response).to have_http_status(:not_found)
    sign_out reader
    get user_avatar_image_path(writer, size: 128)
    expect(response).to redirect_to(new_user_session_path)
  end
end
