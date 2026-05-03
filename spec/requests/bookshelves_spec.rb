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
          is_default: true,
          user_id: other_user.id
        }
      }
    }.to change(user.bookshelves, :count).by(1)

    bookshelf = user.bookshelves.order(:created_at).last
    expect(other_user.bookshelves.count).to eq(1)
    expect(bookshelf.name).to eq("수업 추천")
    expect(bookshelf.visibility).to eq("book_friends")
    expect(bookshelf.is_default).to be(false)
    expect(response).to redirect_to(user_path(user, bookshelf_id: bookshelf.id))
    expect(flash[:notice]).to include("수업 추천")
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

  it "requires a signed-in user" do
    post bookshelves_path, params: { bookshelf: { name: "비로그인 책장", visibility: "public" } }

    expect(response).to redirect_to(new_user_session_path)
  end
end
