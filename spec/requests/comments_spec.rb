require "rails_helper"

RSpec.describe "Comments", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "author@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "댓글 책", authors_text: "저자") }
  let!(:jjaek) { author.jjaeks.create!(book:, content: "Public post") }
  let!(:comment) { jjaek.comments.create!(user:, content: "My comment") }

  it "lets a signed-in user comment on an accessible jjaek" do
    sign_in user

    expect {
      post jjaek_comments_path(jjaek), params: { comment: { content: "Nice note" } }
    }.to change(jjaek.comments, :count).by(1)

    expect(response).to redirect_to(jjaek_path(jjaek))
  end

  it "re-renders the jjaek page when comment creation fails" do
    sign_in user

    post jjaek_comments_path(jjaek), params: { comment: { content: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("대화")
  end

  it "redirects guests to sign in when creating a comment" do
    post jjaek_comments_path(jjaek), params: { comment: { content: "Guest comment" } }

    expect(response).to redirect_to(new_user_session_path)
  end

  it "lets the author update their own comment" do
    sign_in user

    patch jjaek_comment_path(jjaek, comment), params: { comment: { content: "Updated comment" } }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(comment.reload.content).to eq("Updated comment")
  end

  it "does not allow another user to update the comment" do
    sign_in author

    patch jjaek_comment_path(jjaek, comment), params: { comment: { content: "Hijacked" } }

    expect(response).to redirect_to(root_path)
    expect(comment.reload.content).to eq("My comment")
  end

  it "deletes the current user's comment" do
    sign_in user

    expect {
      delete jjaek_comment_path(jjaek, comment)
    }.to change(Comment, :count).by(-1)
  end
end
