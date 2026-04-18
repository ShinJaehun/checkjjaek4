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
end
