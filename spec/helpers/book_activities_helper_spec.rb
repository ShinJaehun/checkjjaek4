require "rails_helper"

RSpec.describe BookActivitiesHelper, type: :helper do
  it "renders each bookshelf entry update value as a separate badge in card messages" do
    user = User.create!(name: "혜정", email: "book-activity-helper@example.com", password: "password123!", password_confirmation: "password123!")
    book = Book.create!(title: "책 제목", authors_text: "저자")
    stickers = [
      StickerDefinition.create!(key: "stayed_with_me", name: "마음에 남아요"),
      StickerDefinition.create!(key: "recommended_to_me", name: "추천받았어요"),
      StickerDefinition.create!(key: "loved_it", name: "좋았어요"),
      StickerDefinition.create!(key: "really_loved_it", name: "너무 좋았어요")
    ]
    activity = BookActivity.create!(
      user:,
      book:,
      action: :bookshelf_entry_updated,
      metadata: {
        from_status: "wish",
        to_status: "reading",
        added_sticker_names: [ "마음에 남아요", "추천받았어요" ],
        added_sticker_definition_ids: stickers.first(2).map(&:id),
        removed_sticker_names: [ "좋았어요", "너무 좋았어요" ],
        removed_sticker_definition_ids: stickers.last(2).map(&:id)
      }
    )

    fragment = Nokogiri::HTML.fragment(helper.book_activity_card_message(activity, context: :book, sticker_definitions: stickers.index_by(&:id)).to_s)
    badge_texts = fragment.css("span").map(&:text)

    expect(badge_texts).to include("읽는 중", "마음에 남아요", "추천받았어요", "좋았어요", "너무 좋았어요")
    expect(badge_texts).not_to include("마음에 남아요, 추천받았어요")
    expect(badge_texts).not_to include("좋았어요, 너무 좋았어요")
    expect(fragment.css("[data-reading-status]").map { |badge| badge["data-reading-status"] }).to eq([ "reading" ])
    expect(fragment.css("[data-reading-sticker]").map { |badge| badge["data-reading-sticker"] }).to eq(stickers.map(&:key))
    expect(fragment.text).not_to include(book.title)
  end

  it "does not infer a reading state from an addition and keeps legacy sticker names" do
    user = User.create!(name: "혜정", email: "book-activity-legacy@example.com", password: "password123!")
    book = Book.create!(title: "책 제목", authors_text: "저자")
    addition = BookActivity.new(user:, book:, action: :added_to_shelf)
    legacy_removal = BookActivity.new(user:, book:, action: :sticker_removed, metadata: { sticker_name: "옛 스티커" })

    addition_html = Nokogiri::HTML.fragment(helper.book_activity_card_message(addition, context: :book).to_s)
    removal_html = Nokogiri::HTML.fragment(helper.book_activity_card_message(legacy_removal, context: :book).to_s)

    expect(addition_html.text).to eq("혜정님이 이 책을 서재에 담았습니다.")
    expect(addition_html.css("[data-reading-status], [data-reading-sticker]")).to be_empty
    expect(removal_html.text).to include("옛 스티커", "제거했습니다")
  end

  it "renders a cleared status and a legacy sticker ID from recorded metadata" do
    user = User.create!(name: "혜정", email: "book-activity-old-actions@example.com", password: "password123!")
    book = Book.create!(title: "책 제목", authors_text: "저자")
    sticker = StickerDefinition.create!(key: "want_to_reread", name: "다시 읽고 싶어요")
    cleared = BookActivity.new(user:, book:, action: :status_cleared, metadata: { from_status: "reading", to_status: nil })
    sticker_added = BookActivity.new(user:, book:, action: :sticker_added, metadata: { sticker_definition_id: sticker.id, sticker_name: sticker.name })

    cleared_html = Nokogiri::HTML.fragment(helper.book_activity_card_message(cleared, context: :book).to_s)
    sticker_html = Nokogiri::HTML.fragment(helper.book_activity_card_message(sticker_added, context: :book, sticker_definitions: { sticker.id => sticker }).to_s)

    expect(cleared_html.text).to include("독서 상태를 비웠습니다.")
    expect(cleared_html.css("[data-reading-status]")).to be_empty
    expect(sticker_html.at_css("[data-reading-sticker]")["data-reading-sticker"]).to eq(sticker.key)
    expect(sticker_html.text).to include("스티커를 붙였습니다.")
  end
end
