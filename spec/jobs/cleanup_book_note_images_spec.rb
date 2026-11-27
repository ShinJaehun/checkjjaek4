require "rails_helper"

RSpec.describe CleanupBookNoteImagesJob, type: :job do
  include ActiveJob::TestHelper

  let(:owner) { User.create!(name: "Reader", email: "note-image-cleanup@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Book for cleanup") }
  let(:user_book) { owner.bookshelf_entries.create!(book:).user_book }

  def create_image(expires_at: 24.hours.from_now)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(Vips::Image.black(8, 8).write_to_buffer(".webp")), filename: "book-note.webp", content_type: "image/webp"
    )
    user_book.book_note_images.create!(user: owner, blob:, state: :temporary, expires_at:)
  end

  after do
    BookNoteImage.where(user: owner).includes(:blob).find_each { |image| image.blob.service.delete(image.blob.key) }
  end

  it "removes expired and detached images while preserving fresh or linked images" do
    expired = create_image(expires_at: 1.minute.ago)
    abandoned = create_image
    abandoned.update!(state: :uploading, expires_at: nil, created_at: 25.hours.ago)
    fresh = create_image
    deleted_note = user_book.book_notes.create!(body: "To remove")
    detached = create_image
    detached.attach_to!(deleted_note, user: owner)
    deleted_note.destroy!
    kept_note = user_book.book_notes.create!(body: "Keep this note")
    linked = create_image
    linked.attach_to!(kept_note, user: owner)
    variant_blob = expired.blob.variant(resize_to_limit: [ 800, 800 ], format: :webp,
      saver: { strip: true, quality: 85 }).processed.image.blob
    expect(variant_blob.service.exist?(variant_blob.key)).to be(true)

    purged_images = [ expired, abandoned, detached ].map do |image|
      [ image, image.blob ]
    end

    perform_enqueued_jobs(only: PurgeBookNoteImageJob) { described_class.perform_now }

    purged_images.each do |image, blob|
      expect(BookNoteImage.exists?(image.id)).to be(false)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
      expect(blob.service.exist?(blob.key)).to be(false)
    end
    expect(BookNoteImage.where(user: owner)).to contain_exactly(fresh, linked)
    expect(linked.blob.service.exist?(linked.blob.key)).to be(true)
    expect(variant_blob.service.exist?(variant_blob.key)).to be(false)
  end

  it "retains the key and byte reservation and schedules a retry when deletion fails" do
    image = create_image(expires_at: 1.minute.ago)
    blob = image.blob
    allow(blob.service).to receive(:delete).with(blob.key).and_raise(IOError, "Deletion interrupted")

    expect { PurgeBookNoteImageJob.perform_now(image.id) }.to have_enqueued_job(PurgeBookNoteImageJob).with(image.id)
    expect(image.reload.blob).to eq(blob)
    expect(blob.reload.byte_size).to be_positive
    expect(blob.service.exist?(blob.key)).to be(true)

    allow(blob.service).to receive(:delete).with(blob.key).and_call_original
    PurgeBookNoteImageJob.perform_now(image.id)
    expect(BookNoteImage.exists?(image.id)).to be(false)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    expect(blob.service.exist?(blob.key)).to be(false)
  end

  it "enforces the note limit and scopes removal to the actual note and its successful save" do
    note = user_book.book_notes.create!(body: "Private note")
    other_note = user_book.book_notes.create!(body: "Different note")
    images = Array.new(4) { create_image.attach_to!(note, user: owner) }
    extra = create_image
    expect { extra.attach_to!(note, user: owner) }.to raise_error(BookNoteImage::AttachmentLimit)
    other_reader = User.create!(name: "Other", email: "note-image-other-reader@example.com", password: "password123!")
    foreign_note = other_reader.bookshelf_entries.create!(book:).user_book.book_notes.create!(body: "Other reader's note")
    expect { extra.attach_to!(foreign_note, user: other_reader) }.to raise_error(ActiveRecord::RecordNotFound)

    image = images.first
    expect { image.discard_from!(other_note, user: owner) }.to raise_error(ActiveRecord::RecordNotFound)
    BookNote.transaction(requires_new: true) do
      image.discard_from!(note, user: owner)
      raise ActiveRecord::Rollback
    end
    expect(image.reload.book_note).to eq(note)
    image.discard_from!(note, user: owner)
    expect(image).to be_purging
    expect(extra.reload.attach_to!(note, user: owner)).to be_attached
  end
end
