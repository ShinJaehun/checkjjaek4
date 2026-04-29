require "rails_helper"

RSpec.describe "Likes", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader2@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "author2@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "좋아요 책", authors_text: "저자") }
  let!(:jjaek) { author.jjaeks.create!(book:, content: "Public jjaek") }

  it "lets a signed-in user like an accessible jjaek" do
    sign_in user

    expect {
      post jjaek_like_path(jjaek)
    }.to change(Like, :count).by(1)
  end

  it "redirects guests to sign in when liking a jjaek" do
    post jjaek_like_path(jjaek)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not create a duplicate like for the same user and jjaek" do
    sign_in user
    jjaek.likes.create!(user:)

    expect {
      post jjaek_like_path(jjaek)
    }.not_to change(Like, :count)
  end

  it "lets the user remove their like" do
    sign_in user
    jjaek.likes.create!(user:)

    expect {
      delete jjaek_like_path(jjaek)
    }.to change(Like, :count).by(-1)
  end

  it "redirects back with an alert when the like does not exist" do
    sign_in user

    delete jjaek_like_path(jjaek)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("좋아요를 찾을 수 없습니다.")
  end
end
