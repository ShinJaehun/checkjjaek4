require "rails_helper"

RSpec.describe "BookshelfEntries", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader-shelf@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book_friend) { User.create!(name: "Friend", email: "friend-shelf@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:stranger) { User.create!(name: "Stranger", email: "stranger-shelf@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:sticker) { StickerDefinition.create!(key: "loved_it", name: "좋았어요") }

  let!(:user_book) { Book.create!(title: "내 서재 책", authors_text: "저자") }
  let!(:friend_book) { Book.create!(title: "친구 서재 책", authors_text: "저자") }
  let!(:stranger_book) { Book.create!(title: "낯선 사람 서재 책", authors_text: "저자") }

  before do
    user.bookshelf_entries.create!(book: user_book, status: :reading)
    book_friend.bookshelf_entries.create!(book: friend_book, status: :wish)
    stranger.bookshelf_entries.create!(book: stranger_book, status: :finished)
    BookFriendship.create!(requester: user, addressee: book_friend, status: :accepted)
  end

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

  it "shows only the signed-in user's bookshelf entries" do
    sign_in user

    get bookshelf_entries_path

    expect(response.body).to include("내 서재 책")
    expect(response.body).not_to include("친구 서재 책")
    expect(response.body).not_to include("낯선 사람 서재 책")
  end
end
