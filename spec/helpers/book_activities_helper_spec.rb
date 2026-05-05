require "rails_helper"

RSpec.describe BookActivitiesHelper, type: :helper do
  it "renders each bookshelf entry update value as a separate badge in card messages" do
    user = User.create!(name: "혜정", email: "book-activity-helper@example.com", password: "password123!", password_confirmation: "password123!")
    book = Book.create!(title: "책 제목", authors_text: "저자")
    activity = BookActivity.create!(
      user:,
      book:,
      action: :bookshelf_entry_updated,
      metadata: {
        from_status: "wish",
        to_status: "reading",
        added_sticker_names: [ "마음에 남아요", "추천받았어요" ],
        removed_sticker_names: [ "좋았어요", "너무 좋았어요" ]
      }
    )

    fragment = Nokogiri::HTML.fragment(helper.book_activity_card_message(activity).to_s)
    badge_texts = fragment.css("span").map(&:text)

    expect(badge_texts).to include("읽는 중", "마음에 남아요", "추천받았어요", "좋았어요", "너무 좋았어요")
    expect(badge_texts).not_to include("마음에 남아요, 추천받았어요")
    expect(badge_texts).not_to include("좋았어요, 너무 좋았어요")
  end
end
