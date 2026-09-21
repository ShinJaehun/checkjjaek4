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
    expect(response.body).not_to include("HIDDEN COMMENT SECRET", "PRIVATE NOTE", hide_admin_jjaek_comment_path(jjaek, comment))

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
    expect(response.body).not_to include("PRIVATE NOTE", hide_admin_jjaek_comment_path(jjaek, comment), restore_admin_jjaek_comment_path(jjaek, comment))
    expect(response.body).not_to include(hide_jjaek_comment_path(jjaek, comment), restore_jjaek_comment_path(jjaek, comment))
  end

  it "shows Group hide and restore forms only to the current Group admin" do
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Display group", group_type: :private_group)
    group.group_memberships.create!(user: author, status: :active)
    group_jjaek = author.jjaeks.create!(group:, content: "Group parent")
    group_comment = group_jjaek.comments.create!(user: author, content: "GROUP COMMENT SECRET")
    sign_in group_admin

    get jjaek_path(group_jjaek)
    expect(response.body).to include(%(action="#{hide_jjaek_comment_path(group_jjaek, group_comment)}"))
    expect(response.body).to include(%(name="moderation_action[public_reason]"), %(name="moderation_action[internal_note]"))
    expect(response.body).not_to include(hide_admin_jjaek_comment_path(group_jjaek, group_comment))

    Comments::Hide.new(group_comment, actor: admin, public_reason: "other", internal_note: "PLATFORM NOTE").call!
    get jjaek_path(group_jjaek)
    expect(response.body).to include("GROUP COMMENT SECRET", "시스템 관리자에 의해 숨겨진 댓글입니다.", "기타")
    expect(response.body).not_to include("PLATFORM NOTE", restore_jjaek_comment_path(group_jjaek, group_comment))

    Comments::Restore.new(group_comment, actor: admin, public_reason: "Resolved").call!
    Comments::Hide.new(group_comment, actor: group_admin, public_reason: "other").call!
    get jjaek_path(group_jjaek)
    expect(response.body).to include("GROUP COMMENT SECRET", "동아리 관리자에 의해 숨겨진 댓글입니다.")
    expect(response.body).to include(%(action="#{restore_jjaek_comment_path(group_jjaek, group_comment)}"))
    expect(response.body).not_to include(restore_admin_jjaek_comment_path(group_jjaek, group_comment))
  end

  it "shows platform controls for another user's comment but author-first for an admin's own comment" do
    own_comment = jjaek.comments.create!(user: admin, content: "ADMIN OWN SECRET")
    sign_in admin

    get jjaek_path(jjaek)
    expect(response.body).to include(%(action="#{hide_admin_jjaek_comment_path(jjaek, comment)}"))
    expect(response.body).not_to include(hide_admin_jjaek_comment_path(jjaek, own_comment))

    group_admin.update!(global_admin: true)
    Comments::Hide.new(comment, actor: group_admin, public_reason: "other").call!
    Comments::Hide.new(own_comment, actor: group_admin, public_reason: "other").call!
    get jjaek_path(jjaek)
    expect(response.body).to include("HIDDEN COMMENT SECRET", %(action="#{restore_admin_jjaek_comment_path(jjaek, comment)}"))
    expect(response.body).to include("ADMIN OWN SECRET")
    expect(response.body).not_to include(restore_admin_jjaek_comment_path(jjaek, own_comment))
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
end
