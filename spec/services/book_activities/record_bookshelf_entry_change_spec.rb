require "rails_helper"

RSpec.describe BookActivities::RecordBookshelfEntryChange do
  let(:user) { User.create!(name: "Reader", email: "activity-service@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "활동 책", authors_text: "저자") }
  let(:entry) { user.bookshelf_entries.create!(book:, status: :reading) }
  let(:first_sticker) { StickerDefinition.create!(key: "service_first", name: "재미있음") }
  let(:second_sticker) { StickerDefinition.create!(key: "service_second", name: "감동") }
  let(:third_sticker) { StickerDefinition.create!(key: "service_third", name: "추천") }

  it "records a status change once" do
    entry.update!(status: :finished)

    expect {
      record_change
    }.to change(BookActivity, :count).by(1)
    expect(BookActivity.last).to have_attributes(action: "bookshelf_entry_updated", metadata: include("from_status" => "reading", "to_status" => "finished"))
  end

  it "records multiple added stickers in one activity" do
    entry.sticker_definitions = [ first_sticker, second_sticker, third_sticker ]

    expect {
      record_change
    }.to change(BookActivity, :count).by(1)
    expect(BookActivity.last.metadata["added_sticker_definition_ids"]).to match_array([ first_sticker.id, second_sticker.id, third_sticker.id ])
  end

  it "records multiple removed stickers in one activity" do
    entry.sticker_definitions = [ first_sticker, second_sticker, third_sticker ]
    previous_ids = entry.sticker_definition_ids
    entry.sticker_definitions = []

    expect {
      record_change(previous_sticker_definition_ids: previous_ids)
    }.to change(BookActivity, :count).by(1)
    expect(BookActivity.last.metadata["removed_sticker_definition_ids"]).to match_array(previous_ids)
  end

  it "records status, added stickers, and removed stickers together" do
    entry.sticker_definitions = [ second_sticker, third_sticker ]
    entry.update!(status: :finished)
    entry.sticker_definitions = [ first_sticker, second_sticker ]

    expect {
      record_change(previous_sticker_definition_ids: [ second_sticker.id, third_sticker.id ])
    }.to change(BookActivity, :count).by(1)
    expect(BookActivity.last.metadata).to include(
      "from_status" => "reading",
      "to_status" => "finished",
      "added_sticker_definition_ids" => [ first_sticker.id ],
      "removed_sticker_definition_ids" => [ third_sticker.id ],
      "added_sticker_names" => [ first_sticker.name ],
      "removed_sticker_names" => [ third_sticker.name ]
    )
  end

  it "does not record activity when nothing changes" do
    entry.sticker_definitions = [ first_sticker ]

    expect {
      record_change(previous_sticker_definition_ids: [ first_sticker.id ])
    }.not_to change(BookActivity, :count)
  end

  it "records a single addition with its personal shelf entry" do
    expect {
      described_class.call(bookshelf_entry: entry, was_new_record: true)
    }.to change(BookActivity, :count).by(1)

    expect(BookActivity.last).to have_attributes(user: user, book: book, bookshelf_entry: entry, action: "added_to_shelf")
  end

  private

  def record_change(previous_sticker_definition_ids: [])
    described_class.call(
      bookshelf_entry: entry,
      was_new_record: false,
      previous_status: "reading",
      previous_sticker_definition_ids: previous_sticker_definition_ids
    )
  end
end
