require "rails_helper"

RSpec.describe "Admin Comment moderation", type: :request do
  let!(:admin) { User.create!(name: "Admin", email: "admin-comment-http@example.com", password: "password123!", global_admin: true) }
  let!(:other_admin) { User.create!(name: "Other admin", email: "other-admin-comment-http@example.com", password: "password123!", global_admin: true) }
  let!(:author) { User.create!(name: "Author", email: "author-comment-http@example.com", password: "password123!") }
  let!(:jjaek) { author.jjaeks.create!(content: "Comment parent") }

  before { sign_in admin }

  it "hides and restores another user's personal comment with platform audit actions" do
    comment = jjaek.comments.create!(user: author, content: "Target")

    patch hide_admin_jjaek_comment_path(jjaek, comment), params: {
      moderation_action: { public_reason: "other", internal_note: "Hide note" }
    }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(flash[:notice]).to eq(I18n.t("comments.moderation.notices.hidden"))
    expect(comment.reload).to be_hidden
    hide = comment.current_hide_action
    expect(hide).to have_attributes(actor: admin, moderation_authority: "platform", public_reason: "other", internal_note: "Hide note")

    patch restore_admin_jjaek_comment_path(jjaek, comment), params: {
      moderation_action: { public_reason: "Resolved", internal_note: "Restore note" }
    }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(comment.reload).not_to be_hidden
    expect(comment.moderation_actions.action_type_restore.sole).to have_attributes(
      actor: admin, moderation_authority: "platform", reversal_of: hide,
      public_reason: "Resolved", internal_note: "Restore note"
    )
  end

  it "hides a Group comment and restores a group-origin hide with platform authority" do
    group_admin = User.create!(name: "Group admin", email: "group-admin-comment-http@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Comment group", group_type: :private_group)
    group_jjaek = author.jjaeks.create!(group:, content: "Group parent")
    comment = group_jjaek.comments.create!(user: author, content: "Group target")

    patch hide_admin_jjaek_comment_path(group_jjaek, comment), params: { moderation_action: { public_reason: "other" } }
    expect(comment.reload.current_hide_action).to have_attributes(moderation_authority: "platform")
    patch restore_admin_jjaek_comment_path(group_jjaek, comment), params: { moderation_action: { public_reason: "Resolved" } }
    expect(comment.reload).not_to be_hidden

    hide = Comments::Hide.new(comment, actor: group_admin, public_reason: "other", internal_note: "Group note").call!.current_hide_action
    patch restore_admin_jjaek_comment_path(group_jjaek, comment), params: { moderation_action: { public_reason: "Platform resolved" } }

    expect(comment.reload).not_to be_hidden
    expect(comment.moderation_actions.action_type_restore.last).to have_attributes(moderation_authority: "platform", reversal_of: hide)
    expect(hide.reload).to have_attributes(moderation_authority: "group", internal_note: "Group note")
  end

  it "rejects self-hide and self-restore" do
    comment = jjaek.comments.create!(user: admin, content: "Own target")

    expect {
      patch hide_admin_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "other" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).not_to be_hidden

    Comments::Hide.new(comment, actor: other_admin, public_reason: "other").call!
    expect {
      patch restore_admin_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "Self restore" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).to be_hidden
  end

  it "rolls back invalid hide and restore reasons" do
    comment = jjaek.comments.create!(user: author, content: "Invalid reason target")

    expect {
      patch hide_admin_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "undefined" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).not_to be_hidden
    expect(flash[:alert]).to eq(I18n.t("comments.moderation.alerts.hide_failed"))

    Comments::Hide.new(comment, actor: admin, public_reason: "other").call!
    expect {
      patch restore_admin_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).to be_hidden
    expect(flash[:alert]).to eq(I18n.t("comments.moderation.alerts.restore_failed"))
  end

  it "rejects a comment ID from another parent on hide" do
    other_jjaek = author.jjaeks.create!(content: "Other parent")
    comment = other_jjaek.comments.create!(user: author, content: "Other comment")

    expect {
      patch hide_admin_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "other" } }
    }.not_to change(ModerationAction, :count)
    expect(response).to have_http_status(:not_found)
    expect(comment.reload).not_to be_hidden
  end

  it "rejects a comment ID from another parent on restore" do
    other_jjaek = author.jjaeks.create!(content: "Other parent")
    comment = other_jjaek.comments.create!(user: author, content: "Other comment")
    Comments::Hide.new(comment, actor: admin, public_reason: "other").call!

    expect {
      patch restore_admin_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "Resolved" } }
    }.not_to change(ModerationAction, :count)
    expect(response).to have_http_status(:not_found)
    expect(comment.reload).to be_hidden
  end
end
