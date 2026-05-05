require "rails_helper"

RSpec.describe BookActivities::RecordBookshelfEntryChange do
  let(:user) { User.create!(name: "Reader", email: "activity-service@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "활동 책", authors_text: "저자") }
  let(:entry) { user.bookshelf_entries.create!(book:, status: :reading) }
  let(:first_sticker) { StickerDefinition.create!(key: "service_first", name: "재미있음") }
  let(:second_sticker) { StickerDefinition.create!(key: "service_second", name: "감동") }
  let(:third_sticker) { StickerDefinition.create!(key: "service_third", name: "추천") }

  it "records one bookshelf_entry_updated activity when only status changes" do
    entry.update!(status: :finished)

    expect {
      record_change(previous_status: "reading", previous_sticker_definition_ids: [])
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include(
      "from_status" => "reading",
      "to_status" => "finished",
      "added_sticker_names" => [],
      "removed_sticker_names" => []
    )
  end

  it "records one bookshelf_entry_updated activity for multiple added stickers" do
    entry.sticker_definitions = [ first_sticker, second_sticker, third_sticker ]

    expect {
      record_change(previous_sticker_definition_ids: [])
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include(
      "added_sticker_definition_ids" => [ first_sticker.id, second_sticker.id, third_sticker.id ],
      "added_sticker_names" => [ "재미있음", "감동", "추천" ],
      "removed_sticker_names" => []
    )
  end

  it "records one bookshelf_entry_updated activity for multiple removed stickers" do
    previous_ids = [ first_sticker.id, second_sticker.id, third_sticker.id ]

    expect {
      record_change(previous_sticker_definition_ids: previous_ids)
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include(
      "added_sticker_names" => [],
      "removed_sticker_definition_ids" => previous_ids,
      "removed_sticker_names" => [ "재미있음", "감동", "추천" ]
    )
  end

  it "records one bookshelf_entry_updated activity when status, added stickers, and removed stickers change together" do
    entry.update!(status: :finished)
    entry.sticker_definitions = [ first_sticker, second_sticker ]

    expect {
      record_change(
        previous_status: "reading",
        previous_sticker_definition_ids: [ second_sticker.id, third_sticker.id ]
      )
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include(
      "from_status" => "reading",
      "to_status" => "finished",
      "added_sticker_names" => [ "재미있음" ],
      "removed_sticker_names" => [ "추천" ]
    )
  end

  it "does not record activity when nothing changes" do
    entry.sticker_definitions = [ first_sticker ]

    expect {
      record_change(previous_status: "reading", previous_sticker_definition_ids: [ first_sticker.id ])
    }.not_to change(BookActivity, :count)
  end

  private

  def record_change(previous_status: entry.status, previous_sticker_definition_ids:)
    described_class.call(
      bookshelf_entry: entry,
      was_new_record: false,
      previous_status: previous_status,
      previous_sticker_definition_ids: previous_sticker_definition_ids
    )
  end
end
