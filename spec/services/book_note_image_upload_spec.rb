require "rails_helper"
require "timeout"

RSpec.describe BookNoteImageUpload, type: :model do
  self.use_transactional_tests = false

  def upload_for(owner_id, user_book_id)
    image = BookNoteImage.new(user: User.find(owner_id), user_book_id:)
    File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"), "rb") do |file|
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "image.png", type: "image/png")
      described_class.new(image:, file: upload).call
    end
  end

  it "allows only one concurrent upload when just one more optimized image fits" do
    owner = User.create!(name: "Reader", email: "note-image-concurrency@example.com", password: "password123!")
    book = Book.create!(title: "Book for concurrent uploads")
    user_book_id = owner.bookshelf_entries.create!(book:).user_book_id
    existing = upload_for(owner.id, user_book_id)
    stub_const("BookNoteImage::STORAGE_LIMIT", 2 * existing.blob.byte_size)

    ready = Queue.new
    start = Queue.new
    allow_any_instance_of(described_class).to receive(:reserve!).and_wrap_original do |reserve, blob|
      ready << true
      start.pop
      reserve.call(blob)
    end

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          upload_for(owner.id, user_book_id)
          :created
        rescue BookNoteImageUpload::Error => error
          error.code
        end
      end
    end

    results = Timeout.timeout(20) do
      2.times { ready.pop }
      2.times { start << true }
      threads.map(&:value)
    end
    expect(results).to contain_exactly(:created, :storage_limit)
    expect(BookNoteImage.where(user: owner).joins(:blob).sum("active_storage_blobs.byte_size")).to eq(BookNoteImage::STORAGE_LIMIT)
  ensure
    Array(threads).each do |thread|
      thread.kill if thread.alive?
      thread.join
    rescue StandardError
      # Thread#value reports upload failures above.
    end
    if owner
      BookNoteImage.where(user: owner).find_each do |image|
        image.update!(state: :purging, expires_at: nil)
        PurgeBookNoteImageJob.perform_now(image.id)
      end
      owner.destroy!
    end
    book&.destroy!
  end
end
