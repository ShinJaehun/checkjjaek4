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

  it "keeps the html fallback redirect when liking a jjaek" do
    sign_in user

    post jjaek_like_path(jjaek)

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq(I18n.t("likes.notices.created"))
  end

  it "replaces only the like summary action on turbo stream like" do
    sign_in user

    expect {
      post jjaek_like_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Like, :count).by(1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="like_action_jjaek_#{jjaek.id}"))
    expect(response.body).to include("좋아요 1개")
    expect(response.body).to include("좋아요 취소")
    expect(response.body).not_to include(jjaek.content)
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

  it "lets the user remove their existing like from a tombstoned jjaek" do
    sign_in user
    jjaek.likes.create!(user:)
    jjaek.comments.create!(user: author, content: "Keeps shell")
    jjaek.destroy_or_tombstone!

    get jjaek_path(jjaek)
    expect(response.body).to include(I18n.t("likes.actions.unlike"))

    expect {
      delete jjaek_like_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Like, :count).by(-1)
    expect(response.body).to include(%(action="remove"))
    expect(response.body).to include(%(target="like_action_jjaek_#{jjaek.id}"))
  end

  it "keeps the html fallback redirect when unliking a jjaek" do
    sign_in user
    jjaek.likes.create!(user:)

    delete jjaek_like_path(jjaek)

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq(I18n.t("likes.notices.destroyed"))
  end

  it "replaces only the like summary action on turbo stream unlike" do
    sign_in user
    jjaek.likes.create!(user:)

    expect {
      delete jjaek_like_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Like, :count).by(-1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="like_action_jjaek_#{jjaek.id}"))
    expect(response.body).to include("좋아요 0개")
    expect(response.body).not_to include("좋아요 취소")
    expect(response.body).not_to include(jjaek.content)
  end

  it "redirects back with an alert when the like does not exist" do
    sign_in user

    delete jjaek_like_path(jjaek)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("좋아요를 찾을 수 없습니다.")
  end
end
