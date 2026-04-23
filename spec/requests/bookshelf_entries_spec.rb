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

  it "only lists the current user's shelf entries on the shelf index" do
    book_friend = User.create!(name: "Book Friend", email: "book-friend-shelf@example.com", password: "password123!", password_confirmation: "password123!")
    user_book = Book.create!(title: "내 서재 책", authors_text: "저자")
    friend_book = Book.create!(title: "친구 서재 책", authors_text: "저자")
    user.bookshelf_entries.create!(book: user_book)
    book_friend.bookshelf_entries.create!(book: friend_book)
    BookFriendship.create!(requester: user, addressee: book_friend, status: :accepted)
    sign_in user

    get bookshelf_entries_path

    expect(response.body).to include(user_book.title)
    expect(response.body).not_to include(friend_book.title)
  end
end
