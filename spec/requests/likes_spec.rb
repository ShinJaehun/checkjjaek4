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

  it "lets an active group member like and unlike general and book jjaeks" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Readers", group_type: :public_group)
    group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    group_book_jjaek = author.jjaeks.create!(group:, book:, content: "Group book jjaek")
    sign_in user

    [ group_jjaek, group_book_jjaek ].each do |record|
      expect { post jjaek_like_path(record) }.to change(record.likes, :count).by(1)
      expect { delete jjaek_like_path(record) }.to change(record.likes, :count).by(-1)
    end
  end

  it "does not let a public group non-member create a like or see the like button" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Public", group_type: :public_group)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    group_jjaek.likes.create!(user: author)
    sign_in user

    expect { post jjaek_like_path(group_jjaek) }.not_to change(Like, :count)

    get jjaek_path(group_jjaek)
    document = Nokogiri::HTML(response.body)
    expect(response.body).to include(I18n.t("jjaeks.meta.likes", count: 1))
    expect(document.at_css(%(form[action="#{jjaek_like_path(group_jjaek)}"] button))).to be_nil
  end

  it "does not create a like for an inactive group or ended membership" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Public", group_type: :public_group)
    membership = group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    sign_in user

    membership.destroy!
    expect { post jjaek_like_path(group_jjaek) }.not_to change(Like, :count)

    group.group_memberships.create!(user:, status: :active)
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    expect { post jjaek_like_path(group_jjaek) }.not_to change(Like, :count)
  end

  it "blocks new likes but allows withdrawing an existing like while activity-suspended" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Moderated likes", group_type: :private_group)
    membership = group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    group_jjaek.likes.create!(user:)
    membership.update!(moderation_status: :activity_suspended)
    sign_in user

    expect { post jjaek_like_path(group_jjaek) }.not_to change(Like, :count)
    expect { delete jjaek_like_path(group_jjaek) }.to change(Like, :count).by(-1)
  end

  it "lets a user remove a visible own like after group closure" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Public", group_type: :public_group)
    membership = group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    sign_in user

    group_jjaek.likes.create!(user:)
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    expect { delete jjaek_like_path(group_jjaek) }.to change(Like, :count).by(-1)
  end

  it "blocks new likes and allows an existing own like to be removed from a tombstoned group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Readers", group_type: :public_group)
    group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    group_jjaek.likes.create!(user:)
    group_jjaek.comments.create!(user: author, content: "Keeps shell")
    group_jjaek.destroy_or_tombstone!
    sign_in user

    expect { post jjaek_like_path(group_jjaek) }.not_to change(Like, :count)
    expect { delete jjaek_like_path(group_jjaek) }.to change(Like, :count).by(-1)
  end

  it "does not remove another user's group like" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Readers", group_type: :public_group)
    group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    other_like = group_jjaek.likes.create!(user: author)
    sign_in user

    expect { delete jjaek_like_path(group_jjaek) }.not_to change(Like, :count)
    expect(other_like.reload).to be_persisted
  end

  it "does not remove an existing like after membership ends and group content access is lost" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    like = group_jjaek.likes.create!(user:)
    membership.destroy!
    sign_in user

    expect { delete jjaek_like_path(group_jjaek) }.not_to change(Like, :count)
    expect(like.reload).to be_persisted
  end

  it "removes the empty like wrapper after a turbo unlike when another like is not allowed" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Public", group_type: :public_group)
    membership = group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    sign_in user

    [
      -> { group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current) },
      -> { membership.destroy! },
      -> {
        group_jjaek.comments.create!(user: author, content: "Keeps shell")
        group_jjaek.destroy_or_tombstone!
      }
    ].each do |make_like_unavailable|
      group.update_columns(lifecycle_status: Group.lifecycle_statuses[:active], closure_reason: nil, closed_at: nil)
      membership = group.group_memberships.find_or_create_by!(user:) { |record| record.status = :active }
      group_jjaek.update_columns(deleted_at: nil, content: "Group jjaek")
      group_jjaek.likes.create!(user:)
      make_like_unavailable.call

      delete jjaek_like_path(group_jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include(%(action="remove"))
      expect(response.body).to include(%(target="like_action_jjaek_#{group_jjaek.id}"))
      get jjaek_path(group_jjaek)
      expect(response.body).not_to include(%(id="like_action_jjaek_#{group_jjaek.id}"))
    end
  end

  it "restores the like button after an active member turbo-unlikes a normal group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Readers", group_type: :public_group)
    group.group_memberships.create!(user:, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group jjaek")
    group_jjaek.likes.create!(user:)
    sign_in user

    delete jjaek_like_path(group_jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    document = Nokogiri::HTML(response.body)
    expect(response.body).to include(%(action="replace"))
    like_button = document.at_css(%(form[action="#{jjaek_like_path(group_jjaek)}"] button))
    expect(like_button&.text).to eq(I18n.t("likes.actions.like"))
  end
end
