require "rails_helper"
require "timeout"

RSpec.describe JjaekPhotoChanges, type: :model do
  let(:writer) { User.create!(name: "Processing", email: "photo-processing@example.com", password: "password123!") }

  before do
    allow(JjaekPhotoUpload).to receive_messages(enabled?: true, daily_limit: 4, retained_limit: 50, storage_limit: 1.gigabyte)
  end

  def change_for(file)
    described_class.new(files: [ file ], remove_ids: [])
  end

  def save_with_photos(jjaek, change)
    return false unless change.prepare(jjaek)

    change.save(jjaek) do |blobs|
      jjaek.photos = blobs
      jjaek.save
    end
  ensure
    change.cleanup
  end

  after do
    JjaekPhotoUpload.original_blobs.find_each { |blob| blob.delete }
  end

  %w[jpeg png webp].each do |format|
    it "decodes #{format} bytes, resizes and strips metadata even with a misleading MIME declaration" do
      Tempfile.create([ "photo", ".#{format}" ]) do |file|
        image = Vips::Image.black(2400, 1200).copy
        image.set_type(GObject::GSTR_TYPE, "exif-ifd0-Artist", "PRIVATE_CAMERA_NAME")
        image.write_to_file(file.path)
        upload = Rack::Test::UploadedFile.new(file.path, "application/octet-stream")
        # Match the HTTP multipart object's type; the MIME declaration is ignored.
        upload = ActionDispatch::Http::UploadedFile.new(tempfile: upload.tempfile, filename: "fake.svg", type: "application/octet-stream")
        jjaek = writer.jjaeks.build(content: "Normalized")
        expect(save_with_photos(jjaek, change_for(upload))).to be(true)
        blob = jjaek.photos.blobs.first
        expect(blob.content_type).to eq("image/webp")
        blob.open do |stored|
          decoded = Vips::Image.new_from_file(stored.path)
          expect([ decoded.width, decoded.height ]).to eq([ 2000, 1000 ])
          expect(decoded.get_fields.grep(/exif|gps/i)).to be_empty
        end
      end
    end
  end

  it "rejects oversized original files and SVG bytes mislabeled as PNG" do
    Tempfile.create([ "unsafe", ".png" ]) do |file|
      file.write('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>')
      file.flush
      [ false, true ].each do |oversized|
        if oversized
          file.truncate(described_class::MAX_SIZE + 1)
          file.flush
        end
        upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "photo.png", type: "image/png")
        jjaek = writer.jjaeks.build(content: "Unsafe")
        change = change_for(upload)
        expect(save_with_photos(jjaek, change)).to be(false)
        error_key = oversized ? "too_large" : "unsupported_format"
        expect(jjaek.errors.full_messages).to include(I18n.t("jjaek_photos.#{error_key}"))
      end
    end
    expect(JjaekPhotoUpload.where(user: writer)).to be_empty
  end

  it "rolls back an OCI failure, preserves previous attachments and keeps keys until physical deletion succeeds" do
    file = File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"))
    upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "photo.png", type: "image/png")
    jjaek = writer.jjaeks.create!(content: "Previous #tag")
    change = change_for(upload)
    expect(change.prepare(jjaek)).to be(true)
    blob = JjaekPhotoUpload.original_blobs.last
    allow(blob.service).to receive(:upload).and_raise(IOError, "Interrupted")
    expect(change.save(jjaek) { |blobs| jjaek.update_attached_books(attributes: { content: "New" }, photos: blobs) }).to be(false)
    expect(jjaek.reload.content).to eq("Previous #tag")
    expect(jjaek.photos).not_to be_attached
    expect(JjaekPhotoUpload.where(user: writer)).to be_empty
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    change.cleanup
    allow(blob.service).to receive(:delete).and_raise(IOError, "Deletion interrupted")
    PurgeJjaekPhotoJob.perform_now(blob.id)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    allow(blob.service).to receive(:delete).and_call_original
    PurgeJjaekPhotoJob.perform_now(blob.id)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  ensure
    file&.close
  end
end

RSpec.describe "Concurrent photo quota", type: :model do
  self.use_transactional_tests = false

  it "commits only one of two simultaneous uploads when one daily slot remains" do
    allow(JjaekPhotoUpload).to receive_messages(enabled?: true, daily_limit: 4, retained_limit: 50, storage_limit: 1.gigabyte)
    writer = User.create!(name: "Concurrent", email: "photo-concurrent@example.com", password: "password123!")
    initial_blob_ids = JjaekPhotoUpload.original_blobs.pluck(:id)
    3.times { JjaekPhotoUpload.create!(user: writer, uploaded_on: Date.current, byte_size: 0) }
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          file = File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"))
          upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "photo.png", type: "image/png")
          change = JjaekPhotoChanges.new(files: [ upload ], remove_ids: [])
          jjaek = Jjaek.new(user_id: writer.id, content: "Concurrent photo")
          raise "Preparation failed" unless change.prepare(jjaek)
          ready << true
          start.pop
          saved = change.save(jjaek) do |blobs|
            jjaek.photos = blobs
            jjaek.save
          end
          results << saved
        ensure
          change&.cleanup
          file&.close
        end
      end
    end
    Timeout.timeout(30) do
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:value)
    end
    expect(2.times.map { results.pop }).to contain_exactly(true, false)
    expect(writer.jjaeks.count).to eq(1)
    expect(JjaekPhotoUpload.where(user: writer, uploaded_on: Date.current).count).to eq(4)
  ensure
    Array(threads).each { |thread| thread.kill if thread.alive? }
    Array(threads).each(&:join)
    if writer
      JjaekPhotoUpload.where(user_id: writer.id).delete_all
      writer.destroy!
      JjaekPhotoUpload.original_blobs.where.not(id: initial_blob_ids).find_each { |blob| PurgeJjaekPhotoJob.perform_now(blob.id) }
    end
  end
end
