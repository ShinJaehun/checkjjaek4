require "rails_helper"

RSpec.describe "Comments", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "author@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:post_record) { author.posts.create!(content: "Public post") }
  let!(:comment) { post_record.comments.create!(user: user, content: "My comment") }

  it "lets a signed-in user comment on an accessible post" do
    sign_in user

    expect {
      post post_comments_path(post_record), params: { comment: { content: "Nice note" } }
    }.to change(post_record.comments, :count).by(1)

    expect(response).to redirect_to(post_path(post_record))
  end

  it "redirects guests to sign in when creating a comment" do
    post post_comments_path(post_record), params: { comment: { content: "Guest comment" } }

    expect(response).to redirect_to(new_user_session_path)
  end

  it "redirects guests to sign in when updating a comment" do
    patch post_comment_path(post_record, comment), params: { comment: { content: "Guest edit" } }

    expect(response).to redirect_to(new_user_session_path)
  end

  it "redirects guests to sign in when deleting a comment" do
    delete post_comment_path(post_record, comment)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "lets the author update their own comment" do
    sign_in user

    patch post_comment_path(post_record, comment), params: { comment: { content: "Updated comment" } }

    expect(response).to redirect_to(post_path(post_record))
    expect(comment.reload.content).to eq("Updated comment")
  end

  it "does not allow another user to update the comment" do
    sign_in author

    patch post_comment_path(post_record, comment), params: { comment: { content: "Hijacked" } }

    expect(response).to redirect_to(root_path)
    expect(comment.reload.content).to eq("My comment")
  end

  it "does not allow another user to delete the comment" do
    sign_in author

    expect {
      delete post_comment_path(post_record, comment)
    }.not_to change(Comment, :count)

    expect(response).to redirect_to(root_path)
    expect(Comment.exists?(comment.id)).to be(true)
  end
end
