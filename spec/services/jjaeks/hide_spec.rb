require "rails_helper"

RSpec.describe Jjaeks::Hide do
  let(:author) { User.create!(name: "Author", email: "hide-service-author@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Admin", email: "hide-service-admin@example.com", password: "password123!", global_admin: true) }
  let(:book) { Book.create!(title: "Moderated book", authors_text: "Author") }

  it "hides every current jjaek context with an audit record" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Moderated group", group_type: :public_group)
    jjaeks = [
      author.jjaeks.create!(content: "General"),
      author.jjaeks.create!(book:, content: "Book"),
      author.jjaeks.create!(group:, content: "Group")
    ]

    jjaeks.each do |jjaek|
      described_class.new(jjaek, actor: admin, public_reason: "inappropriate_content", internal_note: "Reviewed").call!
      action = jjaek.current_hide_action

      expect(jjaek.reload).to be_hidden
      expect(action).to have_attributes(actor: admin, action_type: "hide", public_reason: "inappropriate_content", internal_note: "Reviewed")
    end
  end

  it "preserves the source and existing interactions and requotes" do
    viewer = User.create!(name: "Viewer", email: "hide-service-viewer@example.com", password: "password123!")
    jjaek = author.jjaeks.create!(book:, content: "Preserved source")
    comment = jjaek.comments.create!(user: viewer, content: "Preserved comment")
    like = jjaek.likes.create!(user: viewer)
    requote = viewer.jjaeks.create!(quoted_jjaek: jjaek, content: "Preserved requote")

    described_class.new(jjaek, actor: admin, public_reason: "spam_advertising").call!

    expect(jjaek.reload).to have_attributes(content: "Preserved source", deleted_at: nil)
    expect(jjaek.comments).to contain_exactly(comment)
    expect(jjaek.likes).to contain_exactly(like)
    expect(requote.reload).to have_attributes(quoted_jjaek_id: jjaek.id, quoted_source_deleted_at: nil)
  end

  it "rejects non-admins, duplicate hides, and invalid audits without partial state" do
    jjaek = author.jjaeks.create!(content: "Target")

    expect {
      described_class.new(jjaek, actor: author, public_reason: "other").call!
    }.to raise_error(described_class::InvalidState)
    expect(jjaek.reload).not_to be_hidden

    expect {
      described_class.new(jjaek, actor: admin, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(jjaek.reload).not_to be_hidden
    expect(ModerationAction.where(target: jjaek, action_type: :hide)).to be_empty

    described_class.new(jjaek, actor: admin, public_reason: "other").call!
    expect {
      described_class.new(jjaek, actor: admin, public_reason: "other").call!
    }.to raise_error(described_class::InvalidState)
    expect(ModerationAction.where(target: jjaek, action_type: :hide).count).to eq(1)
  end

  it "rejects a global admin hiding their own jjaek" do
    own_jjaek = admin.jjaeks.create!(content: "Admin authored")

    expect {
      described_class.new(own_jjaek, actor: admin, public_reason: "other").call!
    }.to raise_error(described_class::InvalidState)

    expect(own_jjaek.reload).not_to be_hidden
    expect(own_jjaek.moderation_actions).to be_empty
  end

  it "rolls back the hidden state when audit creation fails" do
    jjaek = author.jjaeks.create!(content: "Atomic target")
    allow(ModerationAction).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(ModerationAction.new))

    expect {
      described_class.new(jjaek, actor: admin, public_reason: "service_disruption").call!
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(jjaek.reload).not_to be_hidden
  end

  it "accepts every defined reason without an internal note and rejects undefined values" do
    Jjaek::MODERATION_HIDE_REASONS.each_with_index do |reason, index|
      jjaek = author.jjaeks.create!(content: "Reason target #{index}")

      described_class.new(jjaek, actor: admin, public_reason: reason).call!

      expect(jjaek.current_hide_action).to have_attributes(public_reason: reason, internal_note: nil)
    end

    invalid = author.jjaeks.create!(content: "Invalid reason target")
    expect {
      described_class.new(invalid, actor: admin, public_reason: "undefined_reason").call!
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(invalid.reload).not_to be_hidden
  end
end
