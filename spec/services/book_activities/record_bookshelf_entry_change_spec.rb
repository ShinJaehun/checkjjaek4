require "rails_helper"

RSpec.describe BookActivities::RecordBookshelfEntryChange do
  let(:user) { User.create!(name: "Reader", email: "activity-service@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "활동 책", authors_text: "저자") }
  let(:entry) { user.bookshelf_entries.create!(book:, status: :reading) }
  let(:first_sticker) { StickerDefinition.create!(key: "service_first", name: "재미있음") }
  let(:second_sticker) { StickerDefinition.create!(key: "service_second", name: "감동") }
  let(:third_sticker) { StickerDefinition.create!(key: "service_third", name: "추천") }

  it "does not record activity when only status changes" do
    entry.update!(status: :finished)

    expect {
      record_change
    }.not_to change(BookActivity, :count)
  end

  it "does not record activity for multiple added stickers" do
    entry.sticker_definitions = [ first_sticker, second_sticker, third_sticker ]

    expect {
      record_change
    }.not_to change(BookActivity, :count)
  end

  it "does not record activity for multiple removed stickers" do
    entry.sticker_definitions = [ first_sticker, second_sticker, third_sticker ]
    entry.sticker_definitions = []

    expect {
      record_change
    }.not_to change(BookActivity, :count)
  end

  it "does not record activity when status, added stickers, and removed stickers change together" do
    entry.sticker_definitions = [ second_sticker, third_sticker ]
    entry.update!(status: :finished)
    entry.sticker_definitions = [ first_sticker, second_sticker ]

    expect {
      record_change
    }.not_to change(BookActivity, :count)
  end

  it "does not record activity when nothing changes" do
    entry.sticker_definitions = [ first_sticker ]

    expect {
      record_change
    }.not_to change(BookActivity, :count)
  end

  it "records a single addition with its personal shelf entry" do
    expect {
      described_class.call(bookshelf_entry: entry, was_new_record: true)
    }.to change(BookActivity, :count).by(1)

    expect(BookActivity.last).to have_attributes(user: user, book: book, bookshelf_entry: entry, action: "added_to_shelf")
  end

  private

  def record_change
    described_class.call(
      bookshelf_entry: entry,
      was_new_record: false
    )
  end
end
