require "rails_helper"

RSpec.describe "Content rate limits", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "rate-reader@example.com", password: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "rate-author@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "Rate limit book", authors_text: "Author") }
  let!(:jjaek) { author.jjaeks.create!(content: "Public note") }
  let(:counter_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:counter_keys) { [] }

  before do
    [ JjaeksController, CommentsController, LikesController ].each do |controller|
      allow(controller.cache_store).to receive(:increment) do |key, amount, **options|
        counter_keys << key
        counter_store.increment(key, amount, **options)
      end
    end
  end

  it "shares 30 writing requests between general and book Jjaeks without creating a blocked post" do
    user.bookshelf_entries.create!(book:)
    sign_in user

    post jjaeks_path, params: { jjaek: { content: "General note" } }
    expect(response).to redirect_to(jjaek_path(Jjaek.order(:id).last))
    post jjaeks_path, params: { jjaek: { book_id: book.id, content: "Book note" } }
    expect(response).to redirect_to(jjaek_path(Jjaek.order(:id).last))
    28.times { post jjaeks_path, params: { jjaek: { content: "" } } }
    expect(response).not_to have_http_status(:too_many_requests)

    jjaek_count = Jjaek.count
    notification_count = Notification.count
    post jjaeks_path, params: { jjaek: { content: "Blocked draft" } },
                      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="flash-messages"), I18n.t("jjaeks.alerts.rate_limited"))
    expect(response.body).not_to include(%(target="jjaek_"))
    expect(Jjaek.count).to eq(jjaek_count)
    expect(Notification.count).to eq(notification_count)
  end

  it "keeps the submitted Jjaek content in an HTML 429 response" do
    sign_in user
    30.times { post jjaeks_path, params: { jjaek: { content: "" } } }

    post jjaeks_path, params: { jjaek: { content: "Unsent draft" } }, headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include("Unsent draft", I18n.t("jjaeks.alerts.rate_limited"))
  end

  it "counts group posts and requotes in the same Jjaek limit" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Readers", group_type: :public_group)
    group.group_memberships.create!(user:, status: :active)
    sign_in user
    29.times { post jjaeks_path, params: { jjaek: { content: "" } } }

    post group_jjaeks_path(group), params: { jjaek: { content: "Group note" } }
    expect(response).to redirect_to(group_path(group))

    jjaek_count = Jjaek.count
    post jjaeks_path(quoted_jjaek_id: jjaek.id), params: { jjaek: { content: "Blocked requote" } },
                                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(Jjaek.count).to eq(jjaek_count)
  end

  it "keeps the Jjaek counter separate for each user" do
    sign_in user
    30.times { post jjaeks_path, params: { jjaek: { content: "" } } }
    sign_out user
    sign_in author

    post jjaeks_path, params: { jjaek: { content: "Author can write" } }

    expect(response).to redirect_to(jjaek_path(Jjaek.order(:id).last))
    expect(Jjaek.order(:id).last.content).to eq("Author can write")
  end

  it "blocks the 31st comment without replacing the Turbo comments panel or creating notifications" do
    sign_in user
    30.times { post jjaek_comments_path(jjaek), params: { comment: { content: "" } } }
    expect(response).not_to have_http_status(:too_many_requests)

    comment_count = Comment.count
    notification_count = Notification.count
    post jjaek_comments_path(jjaek), params: { comment: { content: "Blocked comment" } },
                                     headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="flash-messages"), I18n.t("comments.alerts.rate_limited"))
    expect(response.body).not_to include(%(target="comments_panel_"), %(target="comment_action_"))
    expect(Comment.count).to eq(comment_count)
    expect(Notification.count).to eq(notification_count)
  end

  it "keeps the submitted comment in an HTML 429 response and leaves edit and delete available" do
    own_comment = jjaek.comments.create!(user:, content: "Editable")
    sign_in user
    30.times { post jjaek_comments_path(jjaek), params: { comment: { content: "" } } }

    post jjaek_comments_path(jjaek), params: { comment: { content: "Unsent comment" } },
                                     headers: { "Accept" => "text/html" }
    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include("Unsent comment", I18n.t("comments.alerts.rate_limited"))

    patch jjaek_comment_path(jjaek, own_comment), params: { comment: { content: "Edited" } }
    expect(response).not_to have_http_status(:too_many_requests)
    expect(own_comment.reload.content).to eq("Edited")

    delete jjaek_comment_path(jjaek, own_comment)
    expect(response).not_to have_http_status(:too_many_requests)
    expect(Comment.exists?(own_comment.id)).to be(false)
  end

  it "shares 60 like and unlike requests and leaves the displayed state unchanged on Turbo 429" do
    sign_in user
    30.times do
      post jjaek_like_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      delete jjaek_like_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    expect(response).not_to have_http_status(:too_many_requests)

    notification_count = Notification.count
    post jjaek_like_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="flash-messages"), I18n.t("likes.alerts.rate_limited"))
    expect(response.body).not_to include(%(target="like_action_"))
    expect(jjaek.likes.where(user:).exists?).to be(false)
    expect(Notification.count).to eq(notification_count)
  end

  it "blocks unlike after 60 like requests and shows an HTML 429 message" do
    like = jjaek.likes.create!(user:)
    sign_in user
    60.times { post jjaek_like_path(jjaek) }

    delete jjaek_like_path(jjaek), headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(I18n.t("likes.alerts.rate_limited"))
    expect(Like.exists?(like.id)).to be(true)
  end

  it "keeps unauthenticated requests in the existing sign-in flow without a shared counter" do
    post jjaeks_path, params: { jjaek: { content: "Guest note" } }
    expect(response).to redirect_to(new_user_session_path)
    post jjaek_comments_path(jjaek), params: { comment: { content: "Guest comment" } }
    expect(response).to redirect_to(new_user_session_path)
    post jjaek_like_path(jjaek)
    expect(response).to redirect_to(new_user_session_path)
    expect(counter_keys).to be_empty
  end

  it "keeps the existing content permission check before counting a comment" do
    private_jjaek = author.jjaeks.create!(content: "Private", visibility: :private_jjaek)
    sign_in user

    post jjaek_comments_path(private_jjaek), params: { comment: { content: "Not allowed" } }

    expect(response).to redirect_to(root_path)
    expect(Comment.where(jjaek: private_jjaek)).to be_empty
    expect(counter_keys).to be_empty
  end
end
