require "rails_helper"

RSpec.describe "Comments", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "author@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "댓글 책", authors_text: "저자") }
  let!(:jjaek) { author.jjaeks.create!(book:, content: "Public jjaek") }
  let!(:comment) { jjaek.comments.create!(user:, content: "My comment") }

  it "lets a signed-in user comment on an accessible jjaek" do
    sign_in user

    expect {
      post jjaek_comments_path(jjaek), params: { comment: { content: "Nice note" } }
    }.to change(jjaek.comments, :count).by(1)

    expect(response).to redirect_to(jjaek_path(jjaek))
  end

  it "keeps the html fallback redirect when creating a comment" do
    sign_in user

    post jjaek_comments_path(jjaek), params: { comment: { content: "HTML fallback note" } }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(flash[:notice]).to eq(I18n.t("comments.notices.created"))
  end

  it "replaces only the comments panel on turbo stream comment creation" do
    jjaek.update!(content: "JJAKE_CARD_ONLY_BODY")
    sign_in user

    expect {
      post jjaek_comments_path(jjaek),
           params: { comment: { content: "Turbo panel note" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(jjaek.comments, :count).by(1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).to include("Turbo panel note")
    expect(response.body).to include(%(name="comment[content]"))
    expect(response.body).not_to include("JJAKE_CARD_ONLY_BODY")
  end

  it "creates a notification when another user comments on your jjaek" do
    sign_in user

    expect {
      post jjaek_comments_path(jjaek), params: { comment: { content: "Nice note" } }
    }.to change(Notification, :count).by(1)

    notification = Notification.last
    expect(notification).to be_comment_created
    expect(notification.recipient).to eq(author)
    expect(notification.actor).to eq(user)
    expect(notification.notifiable).to eq(Comment.last)
  end

  it "does not create a notification when commenting on your own jjaek" do
    sign_in author

    expect {
      post jjaek_comments_path(jjaek), params: { comment: { content: "Own note" } }
    }.not_to change(Notification, :count)
  end

  it "re-renders the jjaek page when comment creation fails" do
    sign_in user

    post jjaek_comments_path(jjaek), params: { comment: { content: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("댓글")
    expect(response.body).to include(I18n.t("jjaeks.meta.comments", count: 1))
    expect(response.body).not_to include(I18n.t("jjaeks.meta.comments", count: 2))
  end

  it "shows the comment author's avatar on the jjaek page" do
    sign_in user

    get jjaek_path(jjaek)

    expect(response.body).to include("user_profile_")
    expect(response.body).to include("_128")
    expect(response.body).to include(%(alt="#{user.name}"))
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
