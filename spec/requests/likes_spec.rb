require "rails_helper"

RSpec.describe "Likes", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader2@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "author2@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:post_record) { author.posts.create!(content: "Public post") }

  it "lets a signed-in user like an accessible post" do
    sign_in user

    expect {
      post post_like_path(post_record)
    }.to change(Like, :count).by(1)
  end

  it "redirects guests to sign in when liking a post" do
    post post_like_path(post_record)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "redirects guests to sign in when removing a like" do
    delete post_like_path(post_record)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not create a duplicate like for the same user and post" do
    sign_in user
    post_record.likes.create!(user: user)

    expect {
      post post_like_path(post_record)
    }.not_to change(Like, :count)

    expect(response).to redirect_to(root_path)
  end

  it "lets the user remove their like" do
    sign_in user
    post_record.likes.create!(user: user)

    expect {
      delete post_like_path(post_record)
    }.to change(Like, :count).by(-1)

    expect(response).to redirect_to(root_path)
  end

  it "redirects back with an alert when the like does not exist" do
    sign_in user

    delete post_like_path(post_record)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("좋아요를 찾을 수 없습니다.")
  end
end
