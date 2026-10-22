require "rails_helper"

RSpec.describe "Cleaning up own content after losing group access", type: :request do
  let!(:user) { User.create!(name: "Former reader", email: "cleanup-reader@example.com", password: "password123!") }
  let!(:owner) { User.create!(name: "Private club owner", email: "cleanup-owner@example.com", password: "password123!") }
  let!(:other) { User.create!(name: "Other private reader", email: "cleanup-other@example.com", password: "password123!") }
  let(:group_type) { :private_group }
  let!(:group) { Group.create!(group_admin: owner, name: "Private original club name", group_type:, lifecycle_status: :active) }
  let!(:membership) { group.group_memberships.create!(user:, status: :active) }
  let!(:other_membership) { group.group_memberships.create!(user: other, status: :active) }
  let!(:own_post) { user.jjaeks.create!(group:, content: "MY GROUP POST") }
  let!(:book) { Book.create!(title: "PRIVATE BOOK METADATA", authors_text: "PRIVATE BOOK AUTHOR") }
  let!(:own_book_post) { user.jjaeks.create!(group:, book:, content: "MY BOOK POST") }
  let!(:parent) { other.jjaeks.create!(group:, content: "OTHER PARENT BODY") }
  let!(:own_comment) { parent.comments.create!(user:, content: "MY COMMENT") }
  let!(:foreign_comment) { parent.comments.create!(user: other, content: "OTHER COMMENT BODY") }

  before { sign_in user }

  def leave_group
    delete group_group_membership_path(group, membership)
    expect(response).to redirect_to(groups_path)
  end

  def cleanup_post_ids
    Nokogiri::HTML(response.body).css("[data-cleanup-jjaek-id]").map { |node| node["data-cleanup-jjaek-id"].to_i }
  end

  def cleanup_comment_ids
    Nokogiri::HTML(response.body).css("[data-cleanup-comment-id]").map { |node| node["data-cleanup-comment-id"].to_i }
  end

  it "requires sign in" do
    sign_out user
    get group_path(group.id)
    expect(response).to redirect_to(new_user_session_path)
  end

  it "denies the restricted detail without actual participation even when own content exists" do
    membership.destroy!
    group.group_membership_events.create!(user:, actor: user, event_type: :requested_to_join)
    get group_path(group.id), params: { user_id: owner.id, content: "jjaeks" }
    expect(response).to redirect_to(groups_path)
    expect(response.body).not_to include(own_post.content, own_book_post.content)
  end

  it "keeps other groups out and does not expose a feed through pagination or forged parameters" do
    other_group = Group.create!(group_admin: owner, name: "ANOTHER SECRET GROUP", group_type: :private_group, lifecycle_status: :active)
    other_group.group_membership_events.create!(user:, actor: user, event_type: :left)
    other_post = user.jjaeks.create!(group: other_group, content: "ANOTHER GROUP POST")
    other_comment = other_post.comments.create!(user:, content: "ANOTHER GROUP COMMENT")
    leave_group

    get group_path(group.id), params: { group_id: other_group.id, user_id: other.id, cursor: "forged" },
        headers: { "X-Feed-Pagination" => "true" }, as: :turbo_stream
    expect(response).to have_http_status(:ok)
    expect(cleanup_post_ids).to contain_exactly(own_post.id, own_book_post.id)
    expect(response.body).not_to include(parent.content, other_post.content, other_group.name)
    get group_path(group.id, content: "comments", group_id: other_group.id)
    expect(cleanup_comment_ids).to eq([ own_comment.id ])
    expect(response.body).not_to include(other_comment.content, other_post.content)
  end

  it "binds deletion returns to the actual content group and ignores a forged group ID" do
    foreign_group = Group.create!(group_admin: owner, name: "Foreign return group", lifecycle_status: :active)
    leave_group
    delete jjaek_path(own_post), params: { return_to: "group_restricted_content", group_id: foreign_group.id }
    expect(response).to redirect_to(group_path(group.id))
    delete jjaek_comment_path(parent, own_comment), params: { return_to: "group_restricted_content", group_id: foreign_group.id }
    expect(response).to redirect_to(group_path(group.id, content: "comments"))
    delete jjaek_path(own_book_post), params: { return_to: group_path(foreign_group) }
    expect(response).to redirect_to(groups_path)
  end

  it "links a past card to the existing numeric group route without a separate cleanup page" do
    leave_group
    get groups_path
    card = Nokogiri::HTML(response.body).at_css("[data-past-group-id='#{group.id}']")
    expect(card.at_css("h3 a")["href"]).to eq(group_path(group.id))
    expect(card.text).to include(group.name, I18n.t("groups.past_membership.statuses.left"))
    expect(card.text).not_to include(owner.name, other.name)
    expect(card.css("img, [data-group-members], [data-field='active-member-count']")).to be_empty
    expect(response.body).not_to include("/groups/my_content")
  end

  %i[approval_group private_group].each do |type|
    context "after leaving a #{type}" do
      let(:group_type) { type }

      it "shows only own post bodies and never the group's new name, book metadata, or internal links" do
        leave_group
        group.update!(name: "RENAMED SECRET CLUB", description: "PRIVATE CLUB DESCRIPTION")
        personal = user.jjaeks.create!(content: "PERSONAL POST")
        personal.comments.create!(user:, content: "PERSONAL COMMENT")

        get group_path(group.id, user_id: other.id, jjaek_id: parent.id)

        expect(response).to have_http_status(:ok)
        expect(cleanup_post_ids).to contain_exactly(own_post.id, own_book_post.id)
        expect(response.body).to include(own_post.content, own_book_post.content, I18n.t("groups.restricted_content.group", id: group.id))
        expect(response.body).not_to include(group.name, group.description, parent.content, foreign_comment.content,
                                             book.title, book.authors_text, other.name, "PERSONAL POST", "PERSONAL COMMENT")
        page = Nokogiri::HTML(response.body)
        expect(page.at_css("[data-cleanup-jjaek-id='#{own_book_post.id}']").text).to include(I18n.t("groups.restricted_content.kinds.book"))
        links = page.css("a[href]").map { |link| link["href"] }
        expect(links).not_to include(group_path(group), jjaek_path(own_post), jjaek_path(parent), book_path(book), edit_jjaek_path(own_post))

        get group_path(group.id, content: "comments", user_id: other.id)

        expect(cleanup_comment_ids).to eq([ own_comment.id ])
        expect(response.body).to include(own_comment.content)
        expect(response.body).not_to include(parent.content, foreign_comment.content, group.name, other.name, "PERSONAL COMMENT")
      end
    end
  end

  %i[remove ban].each do |action|
    it "includes own content after a group admin performs #{action}" do
      sign_in owner
      if action == :remove
        delete remove_group_group_membership_path(group, membership)
      else
        post group_group_membership_member_bans_path(group, membership), params: {
          moderation_action: { public_reason: "Repeated rule violations" }
        }
      end
      expect(response).to redirect_to(group_members_path(group))
      expect(GroupMembership.exists?(membership.id)).to be(false)
      expect(group.group_member_bans.exists?(user:)).to be(true) if action == :ban
      sign_in user

      get group_path(group.id)
      expect(cleanup_post_ids).to contain_exactly(own_post.id, own_book_post.id)
      get group_path(group.id, content: "comments")
      expect(cleanup_comment_ids).to eq([ own_comment.id ])
    end
  end

  it "keeps the general detail when membership activity and group operation are suspended" do
    membership.update!(moderation_status: :activity_suspended)
    group.update!(operation_suspended_at: Time.current)
    get group_path(group.id)
    expect(cleanup_post_ids).to be_empty
    expect(response.body).to include(own_post.content, parent.content)
    get group_path(group.id, content: "comments")
    expect(cleanup_comment_ids).to be_empty
  end

  context "with an active public group" do
    let(:group_type) { :public_group }

    it "excludes content after leaving because the group remains readable" do
      leave_group
      get group_path(group.id)
      expect(cleanup_post_ids).to be_empty
      get group_path(group.id, content: "comments")
      expect(cleanup_comment_ids).to be_empty
    end
  end

  it "rechecks current access after rejoining" do
    leave_group
    get group_path(group.id)
    expect(cleanup_post_ids).to include(own_post.id)
    group.group_memberships.create!(user:, status: :active)
    get group_path(group.id)
    expect(cleanup_post_ids).to be_empty
  end

  it "does not expose quote sources when showing the author's own independent body" do
    source = other.jjaeks.create!(book:, content: "RESTRICTED QUOTE SOURCE")
    quote = user.jjaeks.create!(group:, quoted_jjaek: source, content: "MY INDEPENDENT QUOTE BODY")
    source.update!(visibility: :private_jjaek)
    leave_group

    get group_path(group.id)

    expect(cleanup_post_ids).to include(quote.id)
    expect(response.body).to include(quote.content)
    expect(response.body).not_to include(source.content, book.title, other.name)
    expect(JjaekPolicy.new(user, quote).view_quoted_source?).to be(false)
    get jjaek_path(quote)
    expect(response).to have_http_status(:not_found)
  end

  %i[html turbo_stream].each do |format|
    %i[jjaek book comment].each do |kind|
      it "deletes an own #{kind} through #{format} and returns to the correct cleanup list" do
        leave_group
        target = { jjaek: own_post, book: own_book_post, comment: own_comment }.fetch(kind)
        if kind == :comment
          delete jjaek_comment_path(parent, target), params: { return_to: "group_restricted_content" }, as: format
          expect(response).to redirect_to(group_path(group.id, content: "comments"))
          expect(Comment.exists?(target.id)).to be(false)
        else
          delete jjaek_path(target), params: { return_to: "group_restricted_content" }, as: format
          expect(response).to redirect_to(group_path(group.id))
          expect(Jjaek.exists?(target.id)).to be(false)
        end
        expect(response).to have_http_status(:see_other)
        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect(kind == :comment ? cleanup_comment_ids : cleanup_post_ids).not_to include(target.id)
      end
    end
  end

  it "preserves a tombstone and existing comments and allows cleaning up own comments on that tombstone" do
    reply = own_post.comments.create!(user: other, content: "PRESERVED OTHER REPLY")
    own_reply = own_post.comments.create!(user:, content: "MY TOMBSTONE REPLY")
    leave_group

    delete jjaek_path(own_post), params: { return_to: "group_restricted_content" }

    expect(response).to redirect_to(group_path(group.id))
    expect(own_post.reload).to be_deleted
    expect(own_post.content).to eq("")
    expect(own_post.comments).to contain_exactly(reply, own_reply)
    get group_path(group.id)
    expect(cleanup_post_ids).not_to include(own_post.id)
    get group_path(group.id, content: "comments")
    expect(cleanup_comment_ids).to contain_exactly(own_comment.id, own_reply.id)
    expect(response.body).to include(own_reply.content)
    expect(response.body).not_to include(reply.content)
    delete jjaek_comment_path(own_post, own_reply), params: { return_to: "group_restricted_content" }
    expect(response).to redirect_to(group_path(group.id, content: "comments"))
    expect(own_post.reload).to be_deleted
    expect(own_post.comments).to contain_exactly(reply)
    delete jjaek_path(own_post), params: { return_to: "group_restricted_content" }
    expect(response).to redirect_to(root_path)
    expect(own_post.reload).to be_deleted
  end

  it "retains moderation boundaries for hidden posts, hidden comments, and comments on hidden parents" do
    Jjaeks::Hide.new(own_post, actor: owner, public_reason: "other", internal_note: "PRIVATE POST AUDIT").call!
    Comments::Hide.new(own_comment, actor: owner, public_reason: "other", internal_note: "PRIVATE COMMENT AUDIT").call!
    Jjaeks::Hide.new(parent, actor: owner, public_reason: "other").call!
    plain_comment = parent.comments.create!(user:, content: "COMMENT ON HIDDEN PARENT")
    audit_ids = ModerationAction.order(:id).pluck(:id)
    leave_group

    get group_path(group.id)
    expect(cleanup_post_ids).to include(own_post.id)
    expect(response.body).to include(I18n.t("groups.restricted_content.hidden"))
    expect(response.body).not_to include(own_post.content, "PRIVATE POST AUDIT")
    get group_path(group.id, content: "comments")
    expect(cleanup_comment_ids).to contain_exactly(own_comment.id, plain_comment.id)
    expect(response.body).not_to include(own_comment.content, plain_comment.content, parent.content, "PRIVATE COMMENT AUDIT")
    delete jjaek_path(own_post), params: { return_to: "group_restricted_content" }
    expect(response).to redirect_to(group_path(group.id))
    delete jjaek_comment_path(parent, own_comment), params: { return_to: "group_restricted_content" }
    expect(response).to redirect_to(group_path(group.id, content: "comments"))
    expect(ModerationAction.order(:id).pluck(:id)).to eq(audit_ids)
  end

  it "does not grant access, edit, create, or other-author deletion permissions" do
    leave_group
    get group_path(group)
    expect(response).to have_http_status(:ok)
    expect(cleanup_post_ids).to contain_exactly(own_post.id, own_book_post.id)
    get content_group_path(group)
    expect(response).to redirect_to(root_path)
    get root_path
    expect(response.body).not_to include(own_post.content, own_book_post.content, parent.content)
    get user_path(user)
    expect(response.body).not_to include(own_post.content, own_book_post.content, parent.content)
    [ own_post, parent ].each do |record|
      get jjaek_path(record)
      expect(response).to have_http_status(:not_found)
    end
    get jjaek_comments_path(parent), as: :turbo_stream
    expect(response).to have_http_status(:not_found)
    get edit_jjaek_path(own_post)
    expect(response).to have_http_status(:not_found)
    patch jjaek_path(own_post), params: { jjaek: { content: "UNAUTHORIZED EDIT" } }
    expect(response).to have_http_status(:not_found)
    patch jjaek_comment_path(parent, own_comment), params: { comment: { content: "UNAUTHORIZED EDIT" } }
    expect(response).to have_http_status(:not_found)
    post group_jjaeks_path(group), params: { jjaek: { content: "UNAUTHORIZED CREATE" } }
    expect(response).to have_http_status(:not_found)
    post jjaek_comments_path(parent), params: { comment: { content: "UNAUTHORIZED CREATE" } }
    expect(response).to have_http_status(:not_found)
    delete jjaek_path(parent), params: { return_to: "group_restricted_content" }
    expect(response).to redirect_to(root_path)
    delete jjaek_comment_path(parent, foreign_comment), params: { return_to: "group_restricted_content" }
    expect(response).to redirect_to(root_path)
    expect(own_post.reload.content).to eq("MY GROUP POST")
    expect(own_comment.reload.content).to eq("MY COMMENT")
    expect(parent.reload.content).to eq("OTHER PARENT BODY")
    expect(foreign_comment.reload.content).to eq("OTHER COMMENT BODY")
    expect(Jjaek.exists?(content: "UNAUTHORIZED CREATE")).to be(false)
    expect(Comment.exists?(content: "UNAUTHORIZED CREATE")).to be(false)

    sign_in other
    get group_path(group.id, user_id: user.id)
    expect(cleanup_post_ids).to be_empty
    get group_path(group.id, content: "comments", user_id: user.id)
    expect(cleanup_comment_ids).to be_empty
    expect(response.body).not_to include("data-cleanup-")
  end

  [ "https://example.org/steal", "//example.org/steal", "/admin/users" ].each do |destination|
    it "does not accept #{destination} as an arbitrary cleanup return destination" do
      leave_group
      delete jjaek_path(own_book_post), params: { return_to: destination }
      expect(response).to redirect_to(groups_path)
      delete jjaek_comment_path(parent, own_comment), params: { return_to: destination }
      expect(response).to redirect_to(groups_path)
    end
  end

  %i[jjaeks comments].each do |section|
    it "paginates #{section} without loading the full cleanup collection" do
      51.times do |index|
        if section == :comments
          parent.comments.create!(user:, content: "PAGINATED COMMENT #{index}")
        else
          user.jjaeks.create!(group:, content: "PAGINATED POST #{index}")
        end
      end
      leave_group
      get group_path(group.id), params: { content: section, user_id: other.id, host: "example.org", return_to: "https://example.org/steal" }
      first_ids = section == :comments ? cleanup_comment_ids : cleanup_post_ids
      expect(first_ids.size).to eq(Admin::InventoryPage::PER_PAGE)
      next_link = Nokogiri::HTML(response.body).css("a[href]").find { |link| link.text == I18n.t("pagination.next") }
      expect(next_link["href"]).to include("page=2")
      expect(next_link["href"]).to start_with(group_path(group.id))
      expect(next_link["href"]).not_to include("user_id", "example.org", "return_to")
      get next_link["href"]
      remaining_ids = section == :comments ? cleanup_comment_ids : cleanup_post_ids
      expect(first_ids & remaining_ids).to be_empty
      expected_ids = section == :comments ? user.comments.where(jjaek: parent).ids : user.jjaeks.where(group:).ids
      expect(first_ids + remaining_ids).to match_array(expected_ids)
    end
  end
end
