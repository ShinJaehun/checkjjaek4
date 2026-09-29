require "rails_helper"

RSpec.describe "Comment moderation display", type: :request do
  let!(:author) { User.create!(name: "Comment author", email: "display-comment-author@example.com", password: "password123!") }
  let!(:viewer) { User.create!(name: "Viewer", email: "display-comment-viewer@example.com", password: "password123!") }
  let!(:admin) { User.create!(name: "Admin", email: "display-comment-admin@example.com", password: "password123!", global_admin: true) }
  let!(:group_admin) { User.create!(name: "Group admin", email: "display-comment-group-admin@example.com", password: "password123!") }
  let!(:jjaek) { author.jjaeks.create!(content: "Public parent") }
  let!(:comment) { jjaek.comments.create!(user: author, content: "HIDDEN COMMENT SECRET") }

  it "shows only a placeholder and public reason to ordinary readers in HTML and Turbo" do
    Comments::Hide.new(comment, actor: admin, public_reason: "other", internal_note: "PRIVATE NOTE").call!
    sign_in viewer

    get jjaek_path(jjaek)
    expect(response.body).to include("시스템 관리자에 의해 숨겨진 댓글입니다.", "숨김 사유", "기타", "댓글 1개")
    expect(response.body).not_to include("HIDDEN COMMENT SECRET", "PRIVATE NOTE", new_admin_jjaek_comment_restoration_path(jjaek, comment))

    get jjaek_comments_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include("시스템 관리자에 의해 숨겨진 댓글입니다.", "기타")
    expect(response.body).not_to include("HIDDEN COMMENT SECRET", "PRIVATE NOTE")
  end

  it "shows the hidden source and delete to its author without moderation controls" do
    Comments::Hide.new(comment, actor: admin, public_reason: "other", internal_note: "PRIVATE NOTE").call!
    sign_in author

    get jjaek_path(jjaek)

    expect(response.body).to include("HIDDEN COMMENT SECRET", "시스템 관리자에 의해 숨겨진 댓글입니다.", "기타")
    expect(response.body).to include(jjaek_comment_path(jjaek, comment))
    expect(response.body).not_to include("PRIVATE NOTE", new_admin_jjaek_comment_restoration_path(jjaek, comment))
    expect(response.body).not_to include(new_jjaek_comment_group_restoration_path(jjaek, comment))
  end

  it "shows Group hide and restore Action links only to the current Group admin" do
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Display group", group_type: :private_group)
    group.group_memberships.create!(user: author, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group parent")
    group_comment = group_jjaek.comments.create!(user: author, content: "GROUP COMMENT SECRET")
    sign_in group_admin

    get jjaek_path(group_jjaek)
    expect(response.body).to include(%(href="#{new_jjaek_comment_group_hide_path(group_jjaek, group_comment)}"))
    expect(response.body).not_to include(%(name="moderation_action[public_reason]"), %(name="moderation_action[internal_note]"))
    expect(response.body).not_to include(new_admin_jjaek_comment_hide_path(group_jjaek, group_comment))

    Comments::Hide.new(group_comment, actor: admin, public_reason: "other", internal_note: "PLATFORM NOTE").call!
    get jjaek_path(group_jjaek)
    expect(response.body).to include("GROUP COMMENT SECRET", "시스템 관리자에 의해 숨겨진 댓글입니다.", "기타")
    expect(response.body).not_to include("PLATFORM NOTE", new_jjaek_comment_group_restoration_path(group_jjaek, group_comment))

    Comments::Restore.new(group_comment, actor: admin, public_reason: "Resolved").call!
    Comments::Hide.new(group_comment, actor: group_admin, public_reason: "other").call!
    get jjaek_path(group_jjaek)
    expect(response.body).to include("GROUP COMMENT SECRET", "동아리 관리자에 의해 숨겨진 댓글입니다.")
    expect(response.body).to include(%(href="#{new_jjaek_comment_group_restoration_path(group_jjaek, group_comment)}"))
    expect(response.body).not_to include(new_admin_jjaek_comment_restoration_path(group_jjaek, group_comment))
  end

  it "shows platform controls for another user's comment but author-first for an admin's own comment" do
    own_comment = jjaek.comments.create!(user: admin, content: "ADMIN OWN SECRET")
    sign_in admin

    get jjaek_path(jjaek)
    expect(response.body).to include(%(href="#{new_admin_jjaek_comment_hide_path(jjaek, comment)}"))
    expect(response.body).not_to include(new_admin_jjaek_comment_hide_path(jjaek, own_comment))

    group_admin.update!(global_admin: true)
    Comments::Hide.new(comment, actor: group_admin, public_reason: "other").call!
    Comments::Hide.new(own_comment, actor: group_admin, public_reason: "other").call!
    get jjaek_path(jjaek)
    expect(response.body).to include("HIDDEN COMMENT SECRET", %(href="#{new_admin_jjaek_comment_restoration_path(jjaek, comment)}"))
    expect(response.body).to include("ADMIN OWN SECRET")
    expect(response.body).not_to include(new_admin_jjaek_comment_restoration_path(jjaek, own_comment))
  end

  it "keeps visible and hidden comments separate from the parent hide state" do
    visible_comment = jjaek.comments.create!(user: viewer, content: "VISIBLE COMMENT")
    Comments::Hide.new(comment, actor: admin, public_reason: "other").call!
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    sign_in viewer

    get jjaek_comments_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include("VISIBLE COMMENT", "시스템 관리자에 의해 숨겨진 댓글입니다.")
    expect(response.body).not_to include("HIDDEN COMMENT SECRET")
    expect(jjaek.comments.count).to eq(2)
    expect(visible_comment.reload).not_to be_hidden
    expect(comment.reload).to be_hidden
  end

  it "shows chronological platform and group history to another global admin only" do
    Comments::Hide.new(comment, actor: admin, public_reason: "other", internal_note: "PLATFORM HIDE NOTE").call!
    Comments::Restore.new(comment, actor: admin, public_reason: "Platform restored", internal_note: "PLATFORM RESTORE NOTE").call!
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "History group", group_type: :private_group)
    group_jjaek = author.jjaeks.create!(group:, content: "Group history parent")
    group_comment = group_jjaek.comments.create!(user: author, content: "Group history comment")
    Comments::Hide.new(group_comment, actor: group_admin, public_reason: "other", internal_note: "GROUP HIDE NOTE").call!
    Comments::Restore.new(group_comment, actor: admin, public_reason: "Platform group restore", internal_note: "PLATFORM GROUP NOTE").call!
    other_admin = User.create!(name: "Other admin", email: "display-comment-other-admin@example.com", password: "password123!", global_admin: true)
    sign_in other_admin

    get jjaek_path(jjaek)
    document = Nokogiri::HTML(response.body)
    comment_article = document.at_css("#comment_#{comment.id}")
    history = comment_article.at_css("#moderation_history_comment_#{comment.id}")
    expect(history).to be_present
    expect(comment_article.at_css(%(a[href="#{new_admin_jjaek_comment_hide_path(jjaek, comment)}"]))).to be_present
    expect(comment_article.at_css("[data-comment-moderation-state] form")).to be_nil
    expect(history.css("li").map { |entry| entry["data-moderation-action-id"].to_i }).to eq(comment.moderation_actions.order(:created_at, :id).ids)
    expect(history.text).to include("Admin", "시스템 관리자", "PLATFORM HIDE NOTE", "Platform restored", "PLATFORM RESTORE NOTE")
    expect(history.text).to include(I18n.l(comment.moderation_actions.first.created_at, format: :short))

    get jjaek_path(group_jjaek)
    history = Nokogiri::HTML(response.body).at_css("#moderation_history_comment_#{group_comment.id}")
    expect(history.css("li").size).to eq(2)
    expect(history.text).to include("Group admin", "GROUP HIDE NOTE", "Platform group restore", "PLATFORM GROUP NOTE")

    sign_in author
    get jjaek_path(jjaek)
    expect(response.body).not_to include("moderation_history_comment_#{comment.id}", "PLATFORM HIDE NOTE", "PLATFORM RESTORE NOTE")
    sign_in viewer
    get jjaek_path(jjaek)
    expect(response.body).not_to include("moderation_history_comment_#{comment.id}", "PLATFORM HIDE NOTE", "PLATFORM RESTORE NOTE")
  end

  it "shows only group-origin history to the current Group admin" do
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Group history", group_type: :private_group)
    group.group_memberships.create!(user: author, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group history parent")
    group_comment = group_jjaek.comments.create!(user: author, content: "Group history comment")
    Comments::Hide.new(group_comment, actor: group_admin, public_reason: "other", internal_note: "GROUP ONLY NOTE").call!
    Comments::Restore.new(group_comment, actor: admin, public_reason: "Platform restored", internal_note: "PLATFORM ONLY NOTE").call!
    Comments::Hide.new(group_comment, actor: admin, public_reason: "other", internal_note: "PLATFORM HIDE NOTE").call!
    sign_in group_admin

    get jjaek_path(group_jjaek)

    history = Nokogiri::HTML(response.body).at_css("#moderation_history_comment_#{group_comment.id}")
    expect(history.css("li").size).to eq(1)
    expect(history.text).to include("동아리 관리자", "GROUP ONLY NOTE")
    expect(response.body).not_to include("PLATFORM ONLY NOTE", "PLATFORM HIDE NOTE", "Platform restored")
  end

  it "omits an empty panel when writing is forbidden and keeps one when writing is allowed" do
    comment.destroy!
    sign_in viewer

    get jjaek_path(jjaek)
    expect(response.body).to include(%(id="comments_panel_jjaek_#{jjaek.id}"), %(name="comment[content]"))

    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    get jjaek_path(jjaek)
    expect(response.body).not_to include(%(id="comments_panel_jjaek_#{jjaek.id}"))

    get jjaek_comments_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include(%(target="comments_panel_home_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(id="comments_panel_home_jjaek_#{jjaek.id}"))
  end

  it "keeps a panel for a hidden Comment even when new writing is forbidden" do
    Comments::Hide.new(comment, actor: admin, public_reason: "other").call!
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    sign_in viewer

    get jjaek_path(jjaek)

    expect(response.body).to include(%(id="comments_panel_jjaek_#{jjaek.id}"), "시스템 관리자에 의해 숨겨진 댓글입니다.")
    expect(response.body).not_to include("HIDDEN COMMENT SECRET", %(name="comment[content]"))
  end

  it "removes the panel after the final comment is deleted when writing is forbidden" do
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    sign_in author

    delete jjaek_comment_path(jjaek, comment), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include(%(action="replace" target="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body).not_to include(%(id="comments_panel_jjaek_#{jjaek.id}"))
    expect(jjaek.comments.count).to eq(0)
  end

  it "renders platform Action links without inline moderation forms in the Turbo comments panel" do
    sign_in admin
    get jjaek_comments_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(
      %(action="replace" target="comments_panel_home_jjaek_#{jjaek.id}"),
      %(href="#{new_admin_jjaek_comment_hide_path(jjaek, comment)}")
    )
    expect(response.body).not_to include(%(name="moderation_action[public_reason]"))
  end

  it "renders Group Action links without inline moderation forms in the Turbo comments panel" do
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Turbo group", group_type: :private_group)
    group_jjaek = author.jjaeks.create!(group:, content: "Turbo group parent")
    group_comment = group_jjaek.comments.create!(user: author, content: "Turbo group comment")
    sign_in group_admin

    get jjaek_comments_path(group_jjaek),
        params: { comments_context: :group },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include(%(href="#{new_jjaek_comment_group_hide_path(group_jjaek, group_comment)}"))
    expect(response.body).not_to include(%(name="moderation_action[public_reason]"))
  end
end
