require "rails_helper"

RSpec.describe "Comments", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "author@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:post_record) { author.posts.create!(content: "Public post") }

  it "lets a signed-in user comment on an accessible post" do
    sign_in user

    expect {
      post post_comments_path(post_record), params: { comment: { content: "Nice note" } }
    }.to change(post_record.comments, :count).by(1)

    expect(response).to redirect_to(post_path(post_record))
  end
end
