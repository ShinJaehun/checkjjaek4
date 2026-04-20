require "rails_helper"

RSpec.describe "BookshelfEntries", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader-shelf@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:sticker) { StickerDefinition.create!(key: "loved_it", name: "좋았어요") }

  it "adds a searched book to the shelf" do
    sign_in user

    expect {
      post bookshelf_entries_path, params: {
        book: {
          title: "서재의 책",
          authors_text: "저자",
          publisher: "출판사",
          isbn: "1234"
        },
        bookshelf_entry: {
          status: :reading,
          sticker_definition_ids: [ sticker.id ]
        }
      }
    }.to change(BookshelfEntry, :count).by(1)

    expect(response).to redirect_to(book_path(Book.last))
    expect(BookshelfEntry.last.sticker_definitions).to include(sticker)
  end
end
