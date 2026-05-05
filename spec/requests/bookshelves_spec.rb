require "rails_helper"

RSpec.describe "Bookshelves", type: :request do
  let!(:user) { User.create!(name: "Shelf Owner", email: "bookshelves-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:other_user) { User.create!(name: "Other Owner", email: "bookshelves-other@example.com", password: "password123!", password_confirmation: "password123!") }

  it "creates a non-default bookshelf for the current user" do
    sign_in user

    expect {
      post bookshelves_path, params: {
        bookshelf: {
          name: "수업 추천",
          visibility: "book_friends",
          color_key: "purple",
          is_default: true,
          user_id: other_user.id
        }
      }
    }.to change(user.bookshelves, :count).by(1)

    bookshelf = user.bookshelves.order(:created_at).last
    expect(other_user.bookshelves.count).to eq(1)
    expect(bookshelf.name).to eq("수업 추천")
    expect(bookshelf.visibility).to eq("book_friends")
    expect(bookshelf.color_key).to eq("purple")
    expect(bookshelf.is_default).to be(false)
    expect(bookshelf.position).to eq(1)
    expect(response).to redirect_to(user_library_path(user, bookshelf_id: bookshelf.id))
    expect(flash[:notice]).to include("수업 추천")
  end

  it "defaults color_key to stone when creating a bookshelf without color_key" do
    sign_in user

    post bookshelves_path, params: { bookshelf: { name: "기본색 책장", visibility: "public" } }

    expect(user.bookshelves.order(:created_at).last.color_key).to eq("stone")
  end

  it "does not create a duplicate bookshelf name for the same user" do
    user.bookshelves.create!(name: "중복 책장")
    sign_in user

    expect {
      post bookshelves_path, params: { bookshelf: { name: "중복 책장", visibility: "public" } }
    }.not_to change(Bookshelf, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("users.profile.bookshelf_tabs"))
    expect(response.body).to include("중복 책장")
  end

  it "does not create more than twenty bookshelves for one user" do
    19.times { |index| user.bookshelves.create!(name: "Limit Shelf #{index}") }
    sign_in user

    expect {
      post bookshelves_path, params: { bookshelf: { name: "초과 책장", visibility: "private" } }
    }.not_to change(Bookshelf, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("activerecord.errors.models.bookshelf.attributes.base.too_many_bookshelves", count: Bookshelf::MAX_PER_USER))
  end

  it "does not create a bookshelf with an unsupported visibility" do
    sign_in user

    expect {
      post bookshelves_path, params: { bookshelf: { name: "이상한 공개범위", visibility: "everyone" } }
    }.not_to change(Bookshelf, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("users.profile.bookshelf_tabs"))
  end

  it "does not create a bookshelf with an unsupported color_key" do
    sign_in user

    expect {
      post bookshelves_path, params: { bookshelf: { name: "이상한 색상", visibility: "public", color_key: "black" } }
    }.not_to change(Bookshelf, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("users.profile.bookshelf_tabs"))
  end

  it "requires a signed-in user" do
    post bookshelves_path, params: { bookshelf: { name: "비로그인 책장", visibility: "public" } }

    expect(response).to redirect_to(new_user_session_path)
  end

  it "updates an owned non-default bookshelf name, visibility, and color_key" do
    bookshelf = user.bookshelves.create!(name: "수정 전", visibility: :public)
    sign_in user

    patch bookshelf_path(bookshelf), params: { bookshelf: { name: "수정 후", visibility: "private", color_key: "blue", is_default: true } }

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: bookshelf.id))
    expect(bookshelf.reload.name).to eq("수정 후")
    expect(bookshelf.visibility).to eq("private")
    expect(bookshelf.color_key).to eq("blue")
    expect(bookshelf.is_default).to be(false)
    expect(flash[:notice]).to include("수정 후")
  end

  it "does not update the default bookshelf" do
    bookshelf = user.default_bookshelf
    sign_in user

    patch bookshelf_path(bookshelf), params: { bookshelf: { name: "기본 수정", visibility: "private", color_key: "pink", is_default: false } }

    expect(response).to redirect_to(root_path)
    expect(bookshelf.reload.name).to eq(Bookshelf::DEFAULT_NAME)
    expect(bookshelf.visibility).to eq("public")
    expect(bookshelf.color_key).to eq("stone")
    expect(bookshelf.is_default).to be(true)
  end

  it "does not update another user's bookshelf" do
    bookshelf = other_user.bookshelves.create!(name: "남의 책장", visibility: :public)
    sign_in user

    patch bookshelf_path(bookshelf), params: { bookshelf: { name: "가로챈 이름", visibility: "private" } }

    expect(response).to redirect_to(root_path)
    expect(bookshelf.reload.name).to eq("남의 책장")
    expect(bookshelf.visibility).to eq("public")
  end

  it "rerenders the library bookshelf section when update validation fails" do
    user.bookshelves.create!(name: "중복 이름", visibility: :public)
    bookshelf = user.bookshelves.create!(name: "수정 대상", visibility: :book_friends)
    book = Book.create!(title: "수정 실패에도 보이는 책", authors_text: "저자")
    user.bookshelf_entries.create!(book:, bookshelf:)
    sign_in user

    patch bookshelf_path(bookshelf), params: { bookshelf: { name: "중복 이름", visibility: "private" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("users.profile.bookshelf_tabs"))
    expect(response.body).to include("수정 실패에도 보이는 책")
    expect(response.body).to include("중복 이름")
    expect(bookshelf.reload.name).to eq("수정 대상")
    expect(bookshelf.visibility).to eq("book_friends")
  end

  it "rerenders the library bookshelf section when update visibility is unsupported" do
    bookshelf = user.bookshelves.create!(name: "공개범위 수정 대상", visibility: :public)
    sign_in user

    patch bookshelf_path(bookshelf), params: { bookshelf: { name: "공개범위 수정 대상", visibility: "everyone" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("users.profile.bookshelf_tabs"))
    expect(bookshelf.reload.visibility).to eq("public")
  end

  it "rerenders the library bookshelf section when update color_key is unsupported" do
    bookshelf = user.bookshelves.create!(name: "색상 수정 대상", visibility: :public, color_key: "green")
    sign_in user

    patch bookshelf_path(bookshelf), params: { bookshelf: { name: "색상 수정 대상", visibility: "public", color_key: "black" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("users.profile.bookshelf_tabs"))
    expect(bookshelf.reload.color_key).to eq("green")
  end

  it "deletes an empty owned non-default bookshelf" do
    bookshelf = user.bookshelves.create!(name: "빈 책장", visibility: :private)
    default_bookshelf = user.default_bookshelf
    sign_in user

    expect {
      delete bookshelf_path(bookshelf)
    }.to change(user.bookshelves, :count).by(-1)

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: default_bookshelf.id))
    expect(flash[:notice]).to include("빈 책장")
  end

  it "does not delete the default bookshelf" do
    bookshelf = user.default_bookshelf
    sign_in user

    expect {
      delete bookshelf_path(bookshelf)
    }.not_to change(Bookshelf, :count)

    expect(response).to redirect_to(root_path)
    expect(Bookshelf.exists?(bookshelf.id)).to be(true)
  end

  it "does not delete another user's bookshelf" do
    bookshelf = other_user.bookshelves.create!(name: "남의 빈 책장", visibility: :public)
    sign_in user

    expect {
      delete bookshelf_path(bookshelf)
    }.not_to change(Bookshelf, :count)

    expect(response).to redirect_to(root_path)
    expect(Bookshelf.exists?(bookshelf.id)).to be(true)
  end

  it "does not delete a non-empty bookshelf" do
    bookshelf = user.bookshelves.create!(name: "책 있는 책장", visibility: :public)
    book = Book.create!(title: "삭제 막는 책", authors_text: "저자")
    user.bookshelf_entries.create!(book:, bookshelf:)
    sign_in user

    expect {
      delete bookshelf_path(bookshelf)
    }.not_to change(Bookshelf, :count)

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: bookshelf.id))
    expect(flash[:alert]).to be_present
    expect(Bookshelf.exists?(bookshelf.id)).to be(true)
  end

  it "moves an owned regular bookshelf up" do
    first = user.bookshelves.create!(name: "첫 일반")
    second = user.bookshelves.create!(name: "둘째 일반")
    sign_in user

    patch move_up_bookshelf_path(second)

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: second.id))
    expect(ordered_regular_bookshelves(user)).to eq([ second, first ])
  end

  it "moves an owned regular bookshelf down" do
    first = user.bookshelves.create!(name: "첫 일반")
    second = user.bookshelves.create!(name: "둘째 일반")
    sign_in user

    patch move_down_bookshelf_path(first)

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: first.id))
    expect(ordered_regular_bookshelves(user)).to eq([ second, first ])
  end

  it "does not move the default bookshelf" do
    bookshelf = user.default_bookshelf
    sign_in user

    patch move_down_bookshelf_path(bookshelf)

    expect(response).to redirect_to(root_path)
    expect(user.bookshelves.default_first.first).to eq(bookshelf)
  end

  it "does not move another user's bookshelf" do
    bookshelf = other_user.bookshelves.create!(name: "남의 이동 책장")
    sign_in user

    patch move_up_bookshelf_path(bookshelf)

    expect(response).to redirect_to(root_path)
    expect(ordered_regular_bookshelves(other_user)).to eq([ bookshelf ])
  end

  it "keeps order when moving the first regular bookshelf up" do
    first = user.bookshelves.create!(name: "첫 일반")
    second = user.bookshelves.create!(name: "둘째 일반")
    sign_in user

    patch move_up_bookshelf_path(first)

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: first.id))
    expect(ordered_regular_bookshelves(user)).to eq([ first, second ])
  end

  it "keeps order when moving the last regular bookshelf down" do
    first = user.bookshelves.create!(name: "첫 일반")
    second = user.bookshelves.create!(name: "둘째 일반")
    sign_in user

    patch move_down_bookshelf_path(second)

    expect(response).to redirect_to(user_library_path(user, bookshelf_id: second.id))
    expect(ordered_regular_bookshelves(user)).to eq([ first, second ])
  end

  def ordered_regular_bookshelves(owner)
    owner.bookshelves.where(is_default: false).default_first.to_a
  end
end
