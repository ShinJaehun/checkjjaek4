require "rails_helper"

RSpec.describe Comments::Hide do
  let(:author) { User.create!(name: "Comment author", email: "comment-hide-author@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Global admin", email: "comment-hide-admin@example.com", password: "password123!", global_admin: true) }

  it "schedules its exact hide action for the author and returns the comment" do
    comment = author.jjaeks.create!(content: "Source").comments.create!(user: author, content: "Notification target")
    expect(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      expect(moderation_action).to have_attributes(target: comment, actor: admin, action_type: "hide", moderation_authority: "platform")
      expect(moderation_action).to be_persisted
      expect(recipient_ids).to eq([ author.id ])
    end

    expect(described_class.new(comment, actor: admin, public_reason: "other").call!).to eq(comment)
  end

  it "hides a comment and records platform authority" do
    comment = author.jjaeks.create!(content: "Source").comments.create!(user: author, content: "Comment")

    described_class.new(comment, actor: admin, public_reason: "inappropriate_content", internal_note: "Review").call!

    expect(comment.reload).to be_hidden
    expect(comment.current_hide_action).to have_attributes(moderation_authority: "platform", public_reason: "inappropriate_content", internal_note: "Review")
  end

  it "rejects self and duplicate hides and rolls back invalid audits" do
    comment = author.jjaeks.create!(content: "Source").comments.create!(user: author, content: "Comment")

    expect { described_class.new(comment, actor: author, public_reason: "other").call! }.to raise_error(described_class::InvalidState)
    expect(comment.reload).not_to be_hidden

    expect { described_class.new(comment, actor: admin, public_reason: "").call! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(comment.reload).not_to be_hidden
    expect(comment.moderation_actions).to be_empty

    described_class.new(comment, actor: admin, public_reason: "other").call!
    expect { described_class.new(comment, actor: admin, public_reason: "other").call! }.to raise_error(described_class::InvalidState)
  end

  it "hides a group comment and preserves its source" do
    group_admin = User.create!(name: "Comment group admin", email: "comment-hide-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Comment moderation group", group_type: :public_group)
    comment = author.jjaeks.create!(group:, content: "Source").comments.create!(user: author, content: "Comment")

    described_class.new(comment, actor: group_admin, public_reason: "spam_advertising").call!

    expect(comment.reload).to be_hidden
    expect(comment.content).to eq("Comment")
    expect(comment.current_hide_action).to be_group_authority
  end
end
