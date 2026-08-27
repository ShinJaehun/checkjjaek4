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
    expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"))
    expect(response.body).to include("Turbo panel note")
    expect(response.body).to include(I18n.t("jjaeks.meta.comments", count: 2))
    expect(response.body).to include(%(action="update" target="flash-messages"))
    expect(response.body).to include(I18n.t("comments.notices.created"))
    expect(response.body).to include(%(name="comment[content]"))
    expect(response.body).not_to include("JJAKE_CARD_ONLY_BODY")
  end

  it "loads the home inline comments panel on turbo stream index" do
    jjaek.update!(content: "JJAKE_CARD_INDEX_ONLY_BODY")
    sign_in user

    get jjaek_comments_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).to include(comment.content)
    expect(response.body).to include(%(name="comments_context"))
    expect(response.body).to include(%(value="home"))
    expect(response.body).to include(I18n.t("comments.actions.close_inline"))
    expect(response.body).not_to include("JJAKE_CARD_INDEX_ONLY_BODY")
  end

  it "closes the home inline comments panel on turbo stream index" do
    sign_in user

    get jjaek_comments_path(jjaek, comments_context: "home", panel_state: "closed"),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).to include(%(id="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(comment.content)
    expect(response.body).not_to include(%(name="comment[content]"))
  end

  it "ignores closed panel state outside inline comments contexts" do
    sign_in user

    get jjaek_comments_path(jjaek, comments_context: "detail", panel_state: "closed"),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).to include(comment.content)
    expect(response.body).to include(%(name="comment[content]"))
  end

  it "redirects html comments index requests to the detail comments panel anchor" do
    sign_in user

    get jjaek_comments_path(jjaek)

    expect(response).to redirect_to("#{jjaek_path(jjaek)}#comments_panel_jjaek_#{jjaek.id}")
  end

  it "replaces the home comments panel on turbo stream comment creation with home context" do
    sign_in user

    expect {
      post jjaek_comments_path(jjaek),
           params: { comment: { content: "Home panel note" }, comments_context: "home" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(jjaek.comments, :count).by(1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).to include(%(id="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).to include("Home panel note")
    expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"))
  end

  it "loads the profile inline comments panel on turbo stream index" do
    sign_in user

    get jjaek_comments_path(jjaek, comments_context: "profile", profile_user_id: author.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_profile_#{author.id}_jjaek_#{jjaek.id}"))
    expect(response.body).to include(comment.content)
    expect(response.body).to include(%(name="profile_user_id"))
    expect(response.body).to include(%(value="#{author.id}"))
  end

  it "replaces the profile comments panel on turbo stream comment creation with profile context" do
    sign_in user

    expect {
      post jjaek_comments_path(jjaek),
           params: { comment: { content: "Profile panel note" }, comments_context: "profile", profile_user_id: author.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(jjaek.comments, :count).by(1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_profile_#{author.id}_jjaek_#{jjaek.id}"))
    expect(response.body).to include("Profile panel note")
    expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"))
  end

  it "replaces the profile comments panel on turbo stream comment deletion with profile context" do
    comment.update!(content: "PROFILE_COMMENT_TO_DELETE_BODY")
    sign_in user

    expect {
      delete jjaek_comment_path(jjaek, comment),
             params: { comments_context: "profile", profile_user_id: author.id },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Comment, :count).by(-1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_profile_#{author.id}_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include("PROFILE_COMMENT_TO_DELETE_BODY")
    expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"))
  end

  it "loads the book inline comments panel on turbo stream index" do
    sign_in user

    get jjaek_comments_path(jjaek, comments_context: "book", book_id: book.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_book_#{book.id}_jjaek_#{jjaek.id}"))
    expect(response.body).to include(comment.content)
    expect(response.body).to include(%(name="book_id"))
    expect(response.body).to include(%(value="#{book.id}"))
  end

  it "replaces the book comments panel on turbo stream comment creation with book context" do
    sign_in user

    expect {
      post jjaek_comments_path(jjaek),
           params: { comment: { content: "Book panel note" }, comments_context: "book", book_id: book.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(jjaek.comments, :count).by(1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_book_#{book.id}_jjaek_#{jjaek.id}"))
    expect(response.body).to include("Book panel note")
    expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"))
  end

  it "replaces the book comments panel on turbo stream comment deletion with book context" do
    comment.update!(content: "BOOK_COMMENT_TO_DELETE_BODY")
    sign_in user

    expect {
      delete jjaek_comment_path(jjaek, comment),
             params: { comments_context: "book", book_id: book.id },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Comment, :count).by(-1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_book_#{book.id}_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include("BOOK_COMMENT_TO_DELETE_BODY")
    expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"))
  end

  it "falls back to the detail comments panel target for invalid comments context" do
    sign_in user

    post jjaek_comments_path(jjaek),
         params: { comment: { content: "Invalid context note" }, comments_context: "profile" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="comments_panel_home_jjaek_#{jjaek.id}"))
  end

  it "falls back to the detail comments panel target for missing profile context owner" do
    sign_in user

    get jjaek_comments_path(jjaek, comments_context: "profile"),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include("comments_panel_profile_")
  end

  it "falls back to the detail comments panel target when the book context does not match the jjaek" do
    other_book = Book.create!(title: "다른 책", authors_text: "저자")
    sign_in user

    get jjaek_comments_path(jjaek, comments_context: "book", book_id: other_book.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include("comments_panel_book_#{other_book.id}_jjaek_#{jjaek.id}")
  end

  it "falls back to detail when group context is used for a personal Jjaek" do
    sign_in user

    get jjaek_comments_path(jjaek, comments_context: "group"),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="comments_panel_group_jjaek_#{jjaek.id}"))
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

  it "replaces only the comments panel on turbo stream comment creation failure" do
    jjaek.update!(content: "JJAKE_CARD_FAILURE_ONLY_BODY")
    sign_in user

    expect {
      post jjaek_comments_path(jjaek),
           params: { comment: { content: "" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.not_to change(jjaek.comments, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="comment_action_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="flash-messages"))
    expect(response.body).to include(%(name="comment[content]"))
    expect(response.body).to include("field_with_errors")
    expect(response.body).not_to include("JJAKE_CARD_FAILURE_ONLY_BODY")
  end

  it "replaces only the home comments panel on turbo stream comment creation failure with home context" do
    sign_in user

    expect {
      post jjaek_comments_path(jjaek),
           params: { comment: { content: "" }, comments_context: "home" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.not_to change(jjaek.comments, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="comment_action_jjaek_#{jjaek.id}"))
    expect(response.body).to include("field_with_errors")
  end

  it "shows the comment author's avatar on the jjaek page" do
    sign_in user

    get jjaek_path(jjaek)

    expect(response.body).to include("user_profile_")
    expect(response.body).to include("_128")
    expect(response.body).to include(%(alt="#{user.name}"))
    expect(response.body).to include(I18n.t("comments.actions.edit"))
    expect(response.body).not_to include(I18n.t("comments.actions.close_inline"))
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

  it "updates only the requested personal comments panel through Turbo" do
    sign_in user

    patch jjaek_comment_path(jjaek, comment),
          params: { comment: { content: "Home updated" }, comments_context: "home" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(comment.reload.content).to eq("Home updated")
    expect(response.body).to include(%(target="comments_panel_home_jjaek_#{jjaek.id}"), "Home updated")
    expect(response.body).not_to include(%(target="comment_action_jjaek_#{jjaek.id}"))
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

  it "keeps the html fallback redirect when deleting a comment" do
    sign_in user

    delete jjaek_comment_path(jjaek, comment)

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(flash[:notice]).to eq(I18n.t("comments.notices.destroyed"))
  end

  it "replaces only the comments panel on turbo stream comment deletion" do
    jjaek.update!(content: "JJAKE_CARD_DELETE_ONLY_BODY")
    comment.update!(content: "COMMENT_TO_DELETE_BODY")
    remaining_comment = jjaek.comments.create!(user: author, content: "COMMENT_TO_KEEP_BODY")
    sign_in user

    expect {
      delete jjaek_comment_path(jjaek, comment), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Comment, :count).by(-1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"))
    expect(response.body).to include(%(action="update" target="flash-messages"))
    expect(response.body).to include(I18n.t("comments.notices.destroyed"))
    expect(response.body).not_to include("COMMENT_TO_DELETE_BODY")
    expect(response.body).to include(remaining_comment.content)
    expect(response.body).to include(I18n.t("jjaeks.meta.comments", count: 1))
    expect(response.body).not_to include("JJAKE_CARD_DELETE_ONLY_BODY")
  end

  it "replaces the home comments panel on turbo stream comment deletion with home context" do
    comment.update!(content: "HOME_COMMENT_TO_DELETE_BODY")
    sign_in user

    expect {
      delete jjaek_comment_path(jjaek, comment),
             params: { comments_context: "home" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Comment, :count).by(-1)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).to include(%(id="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include("HOME_COMMENT_TO_DELETE_BODY")
    expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"))
  end

  describe "group Jjaek comments" do
    it "lets an active member create a comment and renders the group Turbo panel" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Group comments", group_type: :private_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "Group source")
      sign_in user

      expect {
        post jjaek_comments_path(group_jjaek),
             params: { comment: { content: "Group note" }, comments_context: "group" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change(group_jjaek.comments, :count).by(1)

      expect(response.body).to include(%(target="comments_panel_group_jjaek_#{group_jjaek.id}"))
      expect(response.body).to include(%(target="comment_action_jjaek_#{group_jjaek.id}"))
      expect(response.body).to include("Group note")
    end

    it "does not create a comment after the group is closed" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Closed comments", group_type: :public_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "Existing source")
      group.update!(
        lifecycle_status: :inactive,
        closure_reason: "Test closure",
        closed_at: Time.current
      )
      sign_in user

      expect {
        post jjaek_comments_path(group_jjaek), params: { comment: { content: "Blocked" } }
      }.not_to change(Comment, :count)
    end

    it "lets a public nonmember read comments without showing or accepting the form" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Public comments", group_type: :public_group)
      group_jjaek = author.jjaeks.create!(group:, content: "Public source")
      existing = group_jjaek.comments.create!(user: author, content: "Readable comment")
      sign_in user

      get jjaek_comments_path(group_jjaek, comments_context: "group"),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(existing.content)
      expect(response.body).not_to include(%(name="comment[content]"))

      expect {
        post jjaek_comments_path(group_jjaek), params: { comment: { content: "Blocked" } }
      }.not_to change(Comment, :count)
    end

    it "hides approval and private comment indexes from nonmembers" do
      %i[approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: author, name: group_type.to_s, group_type:)
        group_jjaek = author.jjaeks.create!(group:, content: "Hidden source")
        sign_in user

        get jjaek_comments_path(group_jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:not_found)
      end
    end

    it "hides approval and private comment creation from nonmembers" do
      %i[approval_group private_group].each do |group_type|
        group = Group.create!(lifecycle_status: :active, group_admin: author, name: "#{group_type} create", group_type:)
        group_jjaek = author.jjaeks.create!(group:, content: "Hidden source")
        sign_in user

        post jjaek_comments_path(group_jjaek), params: { comment: { content: "Blocked" } }
        expect(response).to have_http_status(:not_found)
      end
    end

    it "lets an inactive private member see the group but not its Jjaek or comments" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Inactive private", group_type: :private_group)
      membership = group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "Hidden while inactive")
      membership.update!(status: :inactive)
      sign_in user

      get group_path(group)
      expect(response).to have_http_status(:ok)
      get jjaek_path(group_jjaek)
      expect(response).to have_http_status(:not_found)
      get jjaek_comments_path(group_jjaek)
      expect(response).to have_http_status(:not_found)
    end

    it "returns the group panel with 422 on validation failure" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Invalid comment", group_type: :approval_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "Group source")
      sign_in user

      post jjaek_comments_path(group_jjaek),
           params: { comment: { content: "" }, comments_context: "group" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(target="comments_panel_group_jjaek_#{group_jjaek.id}"))
      expect(response.body).not_to include(%(target="comment_action_jjaek_#{group_jjaek.id}"))
    end

    it "updates only the group panel and count when an active member deletes a comment" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Delete comment", group_type: :approval_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "Group source")
      own_comment = group_jjaek.comments.create!(user:, content: "Delete me")
      sign_in user

      expect {
        delete jjaek_comment_path(group_jjaek, own_comment),
               params: { comments_context: "group" },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change(Comment, :count).by(-1)

      expect(response.body).to include(%(target="comments_panel_group_jjaek_#{group_jjaek.id}"))
      expect(response.body).to include(%(target="comment_action_jjaek_#{group_jjaek.id}"))
      expect(response.body).not_to include("Delete me")
    end

    it "lets an inactive or former member delete only their own old comment safely" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Old comments", group_type: :private_group)
      membership = group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "Private source")
      own_comment = group_jjaek.comments.create!(user:, content: "Old comment")
      other_comment = group_jjaek.comments.create!(user: author, content: "Other comment")
      membership.update!(status: :inactive)
      sign_in user

      expect {
        delete jjaek_comment_path(group_jjaek, own_comment),
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change(Comment, :count).by(-1)
      expect(response).to redirect_to(groups_path)
      expect(response.body).not_to include(group_jjaek.content, other_comment.content)

      expect {
        delete jjaek_comment_path(group_jjaek, other_comment)
      }.not_to change(Comment, :count)

      membership.update!(status: :active)
      membership.destroy!
      former_comment = group_jjaek.comments.create!(user:, content: "Former comment")
      expect {
        delete jjaek_comment_path(group_jjaek, former_comment)
      }.to change(Comment, :count).by(-1)
      expect(response).to redirect_to(groups_path)
    end

    it "shows comments but not likes or requotes on a group Jjaek card" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Group card", group_type: :public_group)
      group_jjaek = author.jjaeks.create!(group:, content: "CARD_ACTIONS")
      sign_in user

      get group_path(group)

      expect(response.body).to include(jjaek_comments_path(group_jjaek, comments_context: "group"))
      expect(response.body).not_to include(jjaek_like_path(group_jjaek), new_jjaek_path(quoted_jjaek_id: group_jjaek.id))
    end


    it "shows the form and only the current user's delete action to an active member" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Comment controls", group_type: :approval_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "Controls")
      own_comment = group_jjaek.comments.create!(user:, content: "Mine")
      other_comment = group_jjaek.comments.create!(user: author, content: "Theirs")
      sign_in user

      get jjaek_path(group_jjaek)

      document = Nokogiri::HTML(response.body)
      own_comment_ui = document.at_css("#comment_#{own_comment.id}")
      other_comment_ui = document.at_css("#comment_#{other_comment.id}")

      expect(own_comment_ui.at_css('[data-comment-edit-target="actions"]').text).to match(/수정.*삭제/m)
      expect(own_comment_ui.at_css('[data-comment-edit-target="display"]')["class"]).not_to include("hidden")
      expect(own_comment_ui.at_css('[data-comment-edit-target="form"]')["class"]).to include("hidden")
      expect(
        own_comment_ui
          .at_css('textarea[name="comment[content]"]')
          .text
          .delete_prefix("\n")
      ).to eq(own_comment.content)
      expect(other_comment_ui.at_css('[data-action="comment-edit#open"]')).to be_nil
    end


    it "hides edit but keeps delete for an inactive member's public group comment" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Inactive controls", group_type: :public_group)
      membership = group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "Controls")
      own_comment = group_jjaek.comments.create!(user:, content: "Mine")
      membership.update!(status: :inactive)
      sign_in user

      get jjaek_path(group_jjaek)

      expect(response.body).to include(jjaek_comment_path(group_jjaek, own_comment), I18n.t("comments.actions.delete"))
      expect(response.body).not_to include(I18n.t("comments.actions.edit"), I18n.t("comments.actions.update"))
    end

    it "updates only the group comments panel through Turbo" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Turbo update", group_type: :approval_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "GROUP_CARD_BODY")
      own_comment = group_jjaek.comments.create!(user:, content: "Before update")
      sign_in user

      patch jjaek_comment_path(group_jjaek, own_comment),
            params: { comment: { content: "After update" }, comments_context: "group" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(own_comment.reload.content).to eq("After update")
      expect(response.body).to include(%(target="comments_panel_group_jjaek_#{group_jjaek.id}"), "After update")
      expect(response.body).not_to include(%(target="comment_action_jjaek_#{group_jjaek.id}"), "GROUP_CARD_BODY")
    end

    it "returns the group panel with 422 when a Turbo update is invalid" do
      group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Invalid update", group_type: :approval_group)
      group.group_memberships.create!(user:, status: :active)
      group_jjaek = author.jjaeks.create!(group:, content: "GROUP_UPDATE_FAILURE_BODY")
      own_comment = group_jjaek.comments.create!(user:, content: "Before update")
      sign_in user

      patch jjaek_comment_path(group_jjaek, own_comment),
            params: { comment: { content: "" }, comments_context: "group" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(own_comment.reload.content).to eq("Before update")
      expect(response.body).to include(%(target="comments_panel_group_jjaek_#{group_jjaek.id}"), "field_with_errors")
      expect(response.body).not_to include(%(target="comment_action_jjaek_#{group_jjaek.id}"), "GROUP_UPDATE_FAILURE_BODY")

      document = Nokogiri::HTML(response.body)
      comment_ui = document.at_css("#comment_#{own_comment.id}")
      expect(comment_ui.at_css('[data-comment-edit-target="display"]')["class"]).to include("hidden")
      expect(comment_ui.at_css('[data-comment-edit-target="form"]')["class"]).not_to include("hidden")
      expect(comment_ui.at_css(".field_with_errors")).to be_present
    end
  end
end
