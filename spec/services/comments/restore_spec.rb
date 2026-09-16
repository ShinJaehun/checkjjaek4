require "rails_helper"

RSpec.describe Comments::Restore do
  let(:author) { User.create!(name: "Comment restore author", email: "comment-restore-author@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Comment restore admin", email: "comment-restore-admin@example.com", password: "password123!", global_admin: true) }

  def comment_target
    @comment_target ||= author.jjaeks.create!(content: "Source").comments.create!(user: author, content: "Comment")
  end

  def hide!(actor: admin, authority: "platform")
    if authority == "group"
      Comments::Hide.new(comment_target, actor:, public_reason: "other").call!
    else
      Comments::Hide.new(comment_target, actor:, public_reason: "other").call!
    end
    comment_target.current_hide_action
  end

  it "restores with a separate reason and reversal link" do
    hide = hide!

    described_class.new(comment_target, actor: admin, public_reason: "Reviewed", internal_note: "Restore note").call!

    expect(comment_target.reload).not_to be_hidden
    expect(comment_target.moderation_actions.action_type_restore.sole).to have_attributes(
      moderation_authority: "platform", public_reason: "Reviewed", internal_note: "Restore note", reversal_of: hide
    )
  end

  it "rejects visible and already restored comments and preserves cycles" do
    expect { described_class.new(comment_target, actor: admin, public_reason: "Nope").call! }.to raise_error(described_class::InvalidState)

    hide_a = hide!
    described_class.new(comment_target, actor: admin, public_reason: "Restore A").call!
    hide_b = hide!(actor: admin)
    described_class.new(comment_target, actor: admin, public_reason: "Restore B").call!

    expect(comment_target.reload).not_to be_hidden
    expect(comment_target.moderation_actions.action_type_restore.order(:id).map(&:reversal_of)).to eq([ hide_a, hide_b ])
    expect { described_class.new(comment_target, actor: admin, public_reason: "Duplicate").call! }.to raise_error(described_class::InvalidState)
  end

  it "allows the current group admin to restore a group hide after author promotion" do
    group_admin = User.create!(name: "Group restore admin", email: "comment-restore-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Restore group", group_type: :public_group)
    comment = author.jjaeks.create!(group:, content: "Source").comments.create!(user: author, content: "Comment")
    hide = Comments::Hide.new(comment, actor: group_admin, public_reason: "other").tap(&:call!).then { comment.current_hide_action }
    author.update!(global_admin: true)

    described_class.new(comment, actor: group_admin, public_reason: "Resolved").call!

    expect(comment.reload).not_to be_hidden
    expect(comment.moderation_actions.action_type_restore.sole).to have_attributes(moderation_authority: "group", reversal_of: hide)
  end

  it "rejects group restoration of a platform-origin hide" do
    group_admin = User.create!(name: "Group restore boundary", email: "comment-restore-boundary@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Boundary restore group", group_type: :public_group)
    comment = author.jjaeks.create!(group:, content: "Source").comments.create!(user: author, content: "Comment")
    hide = Comments::Hide.new(comment, actor: admin, public_reason: "other").tap(&:call!).then { comment.current_hide_action }

    expect { described_class.new(comment, actor: group_admin, public_reason: "Blocked").call! }.to raise_error(described_class::InvalidState)
    expect(hide.reload).to be_platform_authority
    expect(comment.reload).to be_hidden
  end

  it "preserves audit rows when the author hard deletes a hidden comment" do
    comment = comment_target
    comment_id = comment.id
    hide = hide!
    comment.destroy!

    expect(hide.reload).to have_attributes(
      target_type: "Comment",
      target_id: comment_id
    )
    expect { Comment.find(comment_id) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
