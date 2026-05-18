require "rails_helper"

RSpec.describe "BookshelfEntries", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader-shelf@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book_friend) { User.create!(name: "Friend", email: "friend-shelf@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:stranger) { User.create!(name: "Stranger", email: "stranger-shelf@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:sticker) { StickerDefinition.create!(key: "bookshelf_entries_spec_loved_it", name: "좋았어요") }

  let!(:user_book) { Book.create!(title: "내 서재 책", authors_text: "저자") }
  let!(:friend_book) { Book.create!(title: "친구 서재 책", authors_text: "저자") }
  let!(:stranger_book) { Book.create!(title: "낯선 사람 서재 책", authors_text: "저자") }

  before do
    user.bookshelf_entries.create!(book: user_book, status: :reading)
    book_friend.bookshelf_entries.create!(book: friend_book, status: :wish)
    stranger.bookshelf_entries.create!(book: stranger_book, status: :finished)
    BookFriendship.create!(requester: user, addressee: book_friend, status: :accepted)
  end

  it "adds a searched book to the shelf without a status" do
    sign_in user

    expect {
      post bookshelf_entries_path, params: {
        book: {
          title: "서재의 책",
          authors_text: "저자",
          publisher: "출판사",
          isbn: "1234"
        }
      }
    }.to change(BookshelfEntry, :count).by(1)

    expect(response).to redirect_to(book_path(Book.last))
    expect(BookshelfEntry.last.status).to be_nil
    expect(BookshelfEntry.last.sticker_definitions).to be_empty
    expect(BookshelfEntry.last.bookshelf).to eq(user.default_bookshelf)
  end

  it "updates the search result card when adding a searched book with Turbo" do
    sign_in user

    expect {
      post bookshelf_entries_path,
           params: {
             bookshelf_entry_source: "book_search",
             book: {
               title: "터보 검색 책",
               authors_text: "저자",
               publisher: "출판사",
               isbn: "turbo-search-001",
               description: "소개",
               external_url: "https://example.com/turbo-search-001"
             }
           },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(BookshelfEntry, :count).by(1)

    target = "book_search_result_#{Digest::SHA256.hexdigest("turbo-search-001")[0, 12]}"
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="replace" target="#{target}"))
    expect(response.body).to include(%(action="update" target="flash-messages"))
    expect(response.body).to include(I18n.t("book_search.actions.in_shelf"))
    expect(response.body).not_to include(I18n.t("book_search.actions.add_to_shelf"))
  end

  it "adds a searched book to the selected owned bookshelf" do
    target_bookshelf = user.bookshelves.create!(name: "선택한 책장", visibility: :private)
    sign_in user

    post bookshelf_entries_path, params: {
      book: {
        title: "선택 책장 책",
        authors_text: "저자",
        isbn: "selected-shelf-001"
      },
      bookshelf_entry: {
        bookshelf_id: target_bookshelf.id
      }
    }

    expect(response).to redirect_to(book_path(Book.last))
    expect(BookshelfEntry.last.bookshelf).to eq(target_bookshelf)
  end

  it "does not add a book to another user's bookshelf" do
    unshelved_book = Book.create!(title: "아직 안 담은 책", authors_text: "저자")
    other_bookshelf = book_friend.bookshelves.create!(name: "다른 사람 책장", visibility: :public)
    sign_in user

    expect {
      post bookshelf_entries_path, params: {
        book_id: unshelved_book.id,
        bookshelf_entry: {
          bookshelf_id: other_bookshelf.id
        }
      }
    }.not_to change(BookshelfEntry, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "does not overwrite the bookshelf when an existing book is posted again" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    original_bookshelf = entry.bookshelf
    target_bookshelf = user.bookshelves.create!(name: "덮어쓰면 안 되는 책장", visibility: :private)
    sign_in user

    expect {
      post bookshelf_entries_path, params: {
        book_id: user_book.id,
        bookshelf_entry: {
          bookshelf_id: target_bookshelf.id
        }
      }
    }.not_to change(BookshelfEntry, :count)

    expect(response).to redirect_to(book_path(user_book))
    expect(entry.reload.bookshelf).to eq(original_bookshelf)
  end

  it "records added_to_shelf when a new book is added" do
    sign_in user

    expect {
      post bookshelf_entries_path, params: {
        book: {
          title: "활동 기록 책",
          authors_text: "저자",
          isbn: "activity-001"
        }
      }
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    entry = BookshelfEntry.last
    expect(activity.action).to eq("added_to_shelf")
    expect(activity.user).to eq(user)
    expect(activity.book).to eq(entry.book)
    expect(activity.bookshelf_entry).to eq(entry)
    expect(activity.metadata).to eq({})
  end

  it "does not record added_to_shelf again when an existing book is added again without changes" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    sign_in user

    expect {
      post bookshelf_entries_path, params: {
        book_id: user_book.id,
        bookshelf_entry: {
          status: entry.status,
          sticker_definition_ids: []
        }
      }
    }.not_to change(BookActivity, :count)

    expect(response).to redirect_to(book_path(user_book))
  end

  it "records update-like changes when an existing book is submitted through create" do
    sign_in user

    expect {
      post bookshelf_entries_path, params: {
        book_id: user_book.id,
        bookshelf_entry: {
          status: :finished,
          sticker_definition_ids: []
        }
      }
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include("from_status" => "reading", "to_status" => "finished")
  end

  it "updates a shelf entry status and stickers" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    sign_in user

    patch bookshelf_entry_path(entry), params: {
      bookshelf_entry: {
        status: :finished,
        sticker_definition_ids: [ sticker.id ]
      }
    }

    expect(response).to redirect_to(book_path(user_book))
    expect(entry.reload.status).to eq("finished")
    expect(entry.sticker_definitions).to include(sticker)
  end

  it "moves the user's own shelf entry to another owned bookshelf" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    target_bookshelf = user.bookshelves.create!(name: "이동 대상 책장", visibility: :private)
    existing_target_book = Book.create!(title: "이미 대상에 있는 책", authors_text: "저자")
    user.bookshelf_entries.create!(book: existing_target_book, bookshelf: target_bookshelf)
    sign_in user

    expect {
      patch move_bookshelf_entry_path(entry), params: { bookshelf_id: target_bookshelf.id }
    }.not_to change(BookshelfEntry, :count)

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: target_bookshelf.id))
    expect(entry.reload.bookshelf).to eq(target_bookshelf)
    expect(entry.position).to eq(2)
    expect(flash[:notice]).to include("이동 대상 책장")
  end

  it "returns to the book page when moving from the book context" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    target_bookshelf = user.bookshelves.create!(name: "책 상세 이동 대상", visibility: :private)
    sign_in user

    patch move_bookshelf_entry_path(entry), params: { bookshelf_id: target_bookshelf.id, return_to: "book" }

    expect(response).to redirect_to(book_path(user_book))
    expect(entry.reload.bookshelf).to eq(target_bookshelf)
    expect(flash[:notice]).to include("책 상세 이동 대상")
  end

  it "keeps the library view and sort when moving from the library context" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    target_bookshelf = user.bookshelves.create!(name: "간단 보기 이동 대상", visibility: :private)
    sign_in user

    patch move_bookshelf_entry_path(entry), params: { bookshelf_id: target_bookshelf.id, return_to: "library", view: "compact", sort: "title" }

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: target_bookshelf.id, view: "compact", sort: "title"))
    expect(entry.reload.bookshelf).to eq(target_bookshelf)
  end

  it "inserts a moved shelf entry before a target shelf entry" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    target_bookshelf = user.bookshelves.create!(name: "앞에 넣을 책장", visibility: :private)
    before_entry = user.bookshelf_entries.create!(book: Book.create!(title: "앞 기준 책", authors_text: "저자"), bookshelf: target_bookshelf)
    after_entry = user.bookshelf_entries.create!(book: Book.create!(title: "뒤 책", authors_text: "저자"), bookshelf: target_bookshelf)
    sign_in user

    patch move_bookshelf_entry_path(entry), params: {
      bookshelf_id: target_bookshelf.id,
      before_entry_id: before_entry.id,
      return_to: "library",
      view: "compact",
      sort: "title"
    }

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: target_bookshelf.id, view: "compact", sort: "manual"))
    expect(target_bookshelf.bookshelf_entries.order(:position).pluck(:id)).to eq([ entry.id, before_entry.id, after_entry.id ])
    expect(entry.reload.position).to eq(1)
    expect(before_entry.reload.position).to eq(2)
    expect(after_entry.reload.position).to eq(3)
  end

  it "rejects moving before another user's shelf entry" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    target_bookshelf = user.bookshelves.create!(name: "내 target 책장", visibility: :private)
    before_entry = book_friend.bookshelf_entries.find_by!(book: friend_book)
    original_bookshelf = entry.bookshelf
    sign_in user

    patch move_bookshelf_entry_path(entry), params: {
      bookshelf_id: target_bookshelf.id,
      before_entry_id: before_entry.id
    }

    expect(response).to have_http_status(:not_found)
    expect(entry.reload.bookshelf).to eq(original_bookshelf)
  end

  it "rejects moving before an entry outside the target bookshelf" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    target_bookshelf = user.bookshelves.create!(name: "삽입 target 책장", visibility: :private)
    other_bookshelf = user.bookshelves.create!(name: "다른 내 책장", visibility: :private)
    before_entry = user.bookshelf_entries.create!(book: Book.create!(title: "다른 책장 기준 책", authors_text: "저자"), bookshelf: other_bookshelf)
    original_bookshelf = entry.bookshelf
    sign_in user

    patch move_bookshelf_entry_path(entry), params: {
      bookshelf_id: target_bookshelf.id,
      before_entry_id: before_entry.id,
      return_to: "library"
    }

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: original_bookshelf.id, sort: "manual"))
    expect(entry.reload.bookshelf).to eq(original_bookshelf)
    expect(target_bookshelf.bookshelf_entries).to be_empty
  end

  it "falls back to detail and omits invalid sort when moving from the library context" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    target_bookshelf = user.bookshelves.create!(name: "잘못된 보기 이동 대상", visibility: :private)
    sign_in user

    patch move_bookshelf_entry_path(entry), params: { bookshelf_id: target_bookshelf.id, return_to: "library", view: "unknown", sort: "unknown" }

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: target_bookshelf.id, view: "detail"))
    expect(entry.reload.bookshelf).to eq(target_bookshelf)
  end

  it "changes only the bookshelf when moving a shelf entry" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    entry.sticker_definitions << sticker
    original_book_id = entry.book_id
    original_user_id = entry.user_id
    original_status = entry.status
    original_sticker_ids = entry.sticker_definition_ids
    target_bookshelf = user.bookshelves.create!(name: "책장 변경만 확인", visibility: :public)
    sign_in user

    patch move_bookshelf_entry_path(entry), params: { bookshelf_id: target_bookshelf.id }

    entry.reload
    expect(entry.bookshelf_id).to eq(target_bookshelf.id)
    expect(entry.book_id).to eq(original_book_id)
    expect(entry.user_id).to eq(original_user_id)
    expect(entry.status).to eq(original_status)
    expect(entry.sticker_definition_ids).to match_array(original_sticker_ids)
  end

  it "does not move another user's shelf entry" do
    entry = book_friend.bookshelf_entries.find_by!(book: friend_book)
    target_bookshelf = user.bookshelves.create!(name: "내 이동 대상 책장", visibility: :public)
    sign_in user

    patch move_bookshelf_entry_path(entry), params: { bookshelf_id: target_bookshelf.id }

    expect(response).to have_http_status(:not_found)
    expect(entry.reload.bookshelf).to eq(book_friend.default_bookshelf)
  end

  it "does not move a shelf entry to another user's bookshelf" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    other_bookshelf = book_friend.bookshelves.create!(name: "다른 사용자 책장", visibility: :public)
    original_bookshelf = entry.bookshelf
    sign_in user

    patch move_bookshelf_entry_path(entry), params: { bookshelf_id: other_bookshelf.id }

    expect(response).to have_http_status(:not_found)
    expect(entry.reload.bookshelf).to eq(original_bookshelf)
  end

  it "returns to the book page when a book-context move fails validation" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    target_bookshelf = user.bookshelves.create!(name: "실패 후 돌아갈 책장", visibility: :private)
    sign_in user
    allow_any_instance_of(BookshelfEntry).to receive(:move_to_bookshelf!) do |record|
      record.errors.add(:base, "이동 실패")
      raise ActiveRecord::RecordInvalid.new(record)
    end

    patch move_bookshelf_entry_path(entry), params: { bookshelf_id: target_bookshelf.id, return_to: "book" }

    expect(response).to redirect_to(book_path(user_book))
    expect(flash[:alert]).to be_present
  end

  it "reorders the user's own shelf entries" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    second_book = Book.create!(title: "순서 변경 책", authors_text: "저자")
    second_entry = user.bookshelf_entries.create!(book: second_book, bookshelf: entry.bookshelf)
    sign_in user

    patch reorder_bookshelf_entries_path, params: {
      bookshelf_id: entry.bookshelf_id,
      bookshelf_entry_ids: [ second_entry.id, entry.id ]
    }

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: entry.bookshelf_id, sort: "manual"))
    expect(second_entry.reload.position).to eq(1)
    expect(entry.reload.position).to eq(2)
  end

  it "keeps the library view when reordering shelf entries" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    second_book = Book.create!(title: "간단 보기 순서 변경 책", authors_text: "저자")
    second_entry = user.bookshelf_entries.create!(book: second_book, bookshelf: entry.bookshelf)
    sign_in user

    patch reorder_bookshelf_entries_path, params: {
      bookshelf_id: entry.bookshelf_id,
      bookshelf_entry_ids: [ second_entry.id, entry.id ],
      view: "compact"
    }

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: entry.bookshelf_id, sort: "manual", view: "compact"))
  end

  it "rejects reordering another user's bookshelf" do
    bookshelf = book_friend.default_bookshelf
    entry = book_friend.bookshelf_entries.find_by!(book: friend_book)
    sign_in user

    patch reorder_bookshelf_entries_path, params: {
      bookshelf_id: bookshelf.id,
      bookshelf_entry_ids: [ entry.id ]
    }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects reordering when another user's entry id is included" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    other_entry = book_friend.bookshelf_entries.find_by!(book: friend_book)
    sign_in user

    patch reorder_bookshelf_entries_path, params: {
      bookshelf_id: entry.bookshelf_id,
      bookshelf_entry_ids: [ entry.id, other_entry.id ]
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(entry.reload.position).to eq(1)
  end

  it "rejects reordering when another owned bookshelf entry id is included" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    other_bookshelf = user.bookshelves.create!(name: "다른 내 책장", visibility: :public)
    other_book = Book.create!(title: "다른 내 책장 책", authors_text: "저자")
    other_entry = user.bookshelf_entries.create!(book: other_book, bookshelf: other_bookshelf)
    sign_in user

    patch reorder_bookshelf_entries_path, params: {
      bookshelf_id: entry.bookshelf_id,
      bookshelf_entry_ids: [ entry.id, other_entry.id ]
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(entry.reload.position).to eq(1)
  end

  it "rejects reordering when an entry id is missing" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    second_book = Book.create!(title: "누락 확인 책", authors_text: "저자")
    user.bookshelf_entries.create!(book: second_book, bookshelf: entry.bookshelf)
    sign_in user

    patch reorder_bookshelf_entries_path, params: {
      bookshelf_id: entry.bookshelf_id,
      bookshelf_entry_ids: [ entry.id ]
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(entry.reload.position).to eq(1)
  end

  it "records bookshelf_entry_updated when a shelf entry status changes" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    sign_in user

    expect {
      patch bookshelf_entry_path(entry), params: {
        bookshelf_entry: {
          status: :finished,
          sticker_definition_ids: []
        }
      }
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include("from_status" => "reading", "to_status" => "finished")
  end

  it "allows a shelf entry status to be cleared" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    sign_in user

    patch bookshelf_entry_path(entry), params: {
      bookshelf_entry: {
        status: "",
        sticker_definition_ids: []
      }
    }

    expect(response).to redirect_to(book_path(user_book))
    expect(entry.reload.status).to be_nil
  end

  it "records bookshelf_entry_updated when a shelf entry status is cleared" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    sign_in user

    expect {
      patch bookshelf_entry_path(entry), params: {
        bookshelf_entry: {
          status: "",
          sticker_definition_ids: []
        }
      }
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include("from_status" => "reading", "to_status" => nil)
  end

  it "does not record activity when the same status is saved again" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    sign_in user

    expect {
      patch bookshelf_entry_path(entry), params: {
        bookshelf_entry: {
          status: :reading,
          sticker_definition_ids: []
        }
      }
    }.not_to change(BookActivity, :count)
  end

  it "records bookshelf_entry_updated when a sticker is added" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    sign_in user

    expect {
      patch bookshelf_entry_path(entry), params: {
        bookshelf_entry: {
          status: :reading,
          sticker_definition_ids: [ sticker.id ]
        }
      }
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include(
      "added_sticker_definition_ids" => [ sticker.id ],
      "added_sticker_names" => [ sticker.name ],
      "removed_sticker_names" => []
    )
  end

  it "records bookshelf_entry_updated when a sticker is removed" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    entry.sticker_definitions << sticker
    sign_in user

    expect {
      patch bookshelf_entry_path(entry), params: {
        bookshelf_entry: {
          status: :reading,
          sticker_definition_ids: []
        }
      }
    }.to change(BookActivity, :count).by(1)

    activity = BookActivity.last
    expect(activity.action).to eq("bookshelf_entry_updated")
    expect(activity.metadata).to include(
      "added_sticker_names" => [],
      "removed_sticker_definition_ids" => [ sticker.id ],
      "removed_sticker_names" => [ sticker.name ]
    )
  end

  it "does not record activity when the sticker list is unchanged" do
    entry = user.bookshelf_entries.find_by!(book: user_book)
    entry.sticker_definitions << sticker
    sign_in user

    expect {
      patch bookshelf_entry_path(entry), params: {
        bookshelf_entry: {
          status: :reading,
          sticker_definition_ids: [ sticker.id ]
        }
      }
    }.not_to change(BookActivity, :count)
  end

  it "does not record activity when a shelf entry save fails" do
    sign_in user

    expect {
      post bookshelf_entries_path, params: {
        book: {
          title: "저장 실패 책",
          authors_text: "저자",
          isbn: "activity-invalid"
        },
        bookshelf_entry: {
          status: "not_a_status",
          sticker_definition_ids: []
        }
      }
    }.not_to change(BookActivity, :count)

    expect(response).to redirect_to(book_search_path)
  end

end
