require "rails_helper"

RSpec.describe "Group Comment moderation", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "group-comment-http@example.com", password: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "group-comment-author-http@example.com", password: "password123!") }
  let!(:global_admin) { User.create!(name: "Global admin", email: "group-comment-global-http@example.com", password: "password123!", global_admin: true) }
  let!(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Moderated comments", group_type: :private_group) }
  let!(:jjaek) { author.jjaeks.create!(group:, content: "Group parent") }
  let!(:comment) { jjaek.comments.create!(user: author, content: "Group comment") }

  before { sign_in group_admin }

  it "hides and restores another user's comment with group audit actions" do
    patch hide_jjaek_comment_path(jjaek, comment), params: {
      moderation_action: { public_reason: "other", internal_note: "Group hide note" }
    }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(comment.reload).to be_hidden
    hide = comment.current_hide_action
    expect(hide).to have_attributes(actor: group_admin, moderation_authority: "group", internal_note: "Group hide note")

    patch restore_jjaek_comment_path(jjaek, comment), params: {
      moderation_action: { public_reason: "Resolved", internal_note: "Group restore note" }
    }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(comment.reload).not_to be_hidden
    expect(comment.moderation_actions.action_type_restore.sole).to have_attributes(
      actor: group_admin, moderation_authority: "group", reversal_of: hide,
      public_reason: "Resolved", internal_note: "Group restore note"
    )
  end

  it "rejects own, personal, other Group, and current global admin comments" do
    own = jjaek.comments.create!(user: group_admin, content: "Own")
    personal_jjaek = author.jjaeks.create!(content: "Personal")
    personal = personal_jjaek.comments.create!(user: author, content: "Personal comment")
    other_group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Other", group_type: :private_group)
    other_jjaek = author.jjaeks.create!(group: other_group, content: "Other group")
    other = other_jjaek.comments.create!(user: author, content: "Other comment")
    admin_comment = jjaek.comments.create!(user: global_admin, content: "Global comment")

    [ [ jjaek, own ], [ personal_jjaek, personal ], [ other_jjaek, other ], [ jjaek, admin_comment ] ].each do |parent, target|
      expect {
        patch hide_jjaek_comment_path(parent, target), params: { moderation_action: { public_reason: "other" } }
      }.not_to change(ModerationAction, :count)
      expect(target.reload).not_to be_hidden
    end

    Comments::Hide.new(own, actor: global_admin, public_reason: "other").call!
    expect {
      patch restore_jjaek_comment_path(jjaek, own), params: { moderation_action: { public_reason: "Self restore" } }
    }.not_to change(ModerationAction, :count)
    expect(own.reload).to be_hidden
  end

  it "restores an existing group hide after author promotion while author self-restore stays forbidden" do
    hide = Comments::Hide.new(comment, actor: group_admin, public_reason: "other").call!.current_hide_action
    author.update!(global_admin: true)

    sign_in author
    expect {
      patch restore_admin_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "Self restore" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).to be_hidden

    sign_in group_admin
    patch restore_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "Resolved" } }
    expect(comment.reload).not_to be_hidden
    expect(comment.moderation_actions.action_type_restore.sole).to have_attributes(moderation_authority: "group", reversal_of: hide)
    expect(hide.reload).to be_group_authority
  end

  it "rejects platform-origin restore and invalid reasons without changing state or audit" do
    expect {
      patch hide_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "undefined" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).not_to be_hidden

    Comments::Hide.new(comment, actor: group_admin, public_reason: "other").call!
    expect {
      patch restore_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).to be_hidden

    Comments::Restore.new(comment, actor: group_admin, public_reason: "Resolved").call!
    Comments::Hide.new(comment, actor: global_admin, public_reason: "other").call!
    expect {
      patch restore_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "Blocked" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).to be_hidden
  end

  it "blocks new hides in an inactive group but restores a hide created before closure" do
    hidden_before_closure = jjaek.comments.create!(user: author, content: "Hidden before closure")
    new_target = jjaek.comments.create!(user: author, content: "New inactive target")
    Comments::Hide.new(hidden_before_closure, actor: group_admin, public_reason: "other").call!
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)

    expect {
      patch hide_jjaek_comment_path(jjaek, new_target), params: { moderation_action: { public_reason: "other" } }
    }.not_to change(ModerationAction, :count)
    expect(new_target.reload).not_to be_hidden

    patch restore_jjaek_comment_path(jjaek, hidden_before_closure), params: {
      moderation_action: { public_reason: "Resolved" }
    }
    expect(hidden_before_closure.reload).not_to be_hidden
  end

  it "rejects pending and operation-suspended Groups" do
    pending_group = Group.create!(group_admin:, name: "Pending", group_type: :private_group, application_purpose: "Pending")
    suspended_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Suspended", group_type: :private_group, operation_suspended_at: Time.current)

    [ pending_group, suspended_group ].each do |target_group|
      parent = author.jjaeks.create!(group: target_group, content: "Restricted parent")
      target = parent.comments.create!(user: author, content: "Restricted comment")
      expect {
        patch hide_jjaek_comment_path(parent, target), params: { moderation_action: { public_reason: "other" } }
      }.not_to change(ModerationAction, :count)
      expect(target.reload).not_to be_hidden

      target.update!(hidden_at: Time.current)
      ModerationAction.create!(target:, actor: group_admin, action_type: :hide, public_reason: "other", moderation_authority: "group")
      expect {
        patch restore_jjaek_comment_path(parent, target), params: { moderation_action: { public_reason: "Blocked" } }
      }.not_to change(ModerationAction, :count)
      expect(target.reload).to be_hidden
    end
  end

  it "moves moderation authority to the current Group admin" do
    new_admin = User.create!(name: "New admin", email: "new-group-comment-http@example.com", password: "password123!")
    group.group_memberships.create!(user: new_admin, status: :active)
    hide = Comments::Hide.new(comment, actor: group_admin, public_reason: "other").call!.current_hide_action
    group.transfer_admin_to!(new_admin, by: group_admin)

    expect {
      patch restore_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "Blocked" } }
    }.not_to change(ModerationAction, :count)
    expect(comment.reload).to be_hidden

    sign_in new_admin
    patch restore_jjaek_comment_path(jjaek, comment), params: { moderation_action: { public_reason: "Resolved" } }
    expect(comment.reload).not_to be_hidden
    expect(comment.moderation_actions.action_type_restore.sole).to have_attributes(actor: new_admin, moderation_authority: "group", reversal_of: hide)
  end

  it "rejects a comment ID from another parent on hide" do
    other_jjaek = author.jjaeks.create!(group:, content: "Other parent")
    other_comment = other_jjaek.comments.create!(user: author, content: "Other comment")

    expect {
      patch hide_jjaek_comment_path(jjaek, other_comment), params: { moderation_action: { public_reason: "other" } }
    }.not_to change(ModerationAction, :count)
    expect(response).to have_http_status(:not_found)
    expect(other_comment.reload).not_to be_hidden
  end

  it "rejects a comment ID from another parent on restore" do
    other_jjaek = author.jjaeks.create!(group:, content: "Other parent")
    other_comment = other_jjaek.comments.create!(user: author, content: "Other comment")
    Comments::Hide.new(other_comment, actor: group_admin, public_reason: "other").call!

    expect {
      patch restore_jjaek_comment_path(jjaek, other_comment), params: { moderation_action: { public_reason: "Resolved" } }
    }.not_to change(ModerationAction, :count)
    expect(response).to have_http_status(:not_found)
    expect(other_comment.reload).to be_hidden
  end
end
