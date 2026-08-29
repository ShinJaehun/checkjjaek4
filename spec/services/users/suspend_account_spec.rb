require "rails_helper"

RSpec.describe Users::SuspendAccount do
  let(:actor) { User.create!(name: "Admin", email: "suspend-service-admin@example.com", password: "password123!", global_admin: true) }
  let(:user) { User.create!(name: "Reader", email: "suspend-service-reader@example.com", password: "password123!") }

  it "suspends the user and records the audit action without changing existing data" do
    other = User.create!(name: "Other", email: "suspend-service-other@example.com", password: "password123!")
    jjaek = user.jjaeks.create!(content: "Preserved public content")
    comment = user.comments.create!(jjaek: other.jjaeks.create!(content: "Conversation"), content: "Preserved comment")
    user.active_follows.create!(followee: other)
    user.requested_book_friendships.create!(addressee: other, status: :accepted)
    user.likes.create!(jjaek: comment.jjaek)
    book = Book.create!(title: "Preserved book", authors_text: "Author")
    entry = user.bookshelf_entries.create!(book:)
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Preserved group", group_type: :public_group)

    expect {
      described_class.new(user, actor:, public_reason: "Policy violation", internal_note: "Case 1").call!
    }.to change(ModerationAction, :count).by(1)

    action = ModerationAction.last
    expect(user.reload).to be_suspended
    expect(action.attributes.slice("target_type", "target_id", "actor_id", "action_type", "public_reason", "internal_note")).to eq(
      "target_type" => "User",
      "target_id" => user.id,
      "actor_id" => actor.id,
      "action_type" => "suspend",
      "public_reason" => "Policy violation",
      "internal_note" => "Case 1"
    )
    expect(user.jjaeks).to contain_exactly(jjaek)
    expect(user.comments).to contain_exactly(comment)
    expect(user.active_follows).to exist
    expect(user.requested_book_friendships).to exist
    expect(user.likes).to exist
    expect(user.bookshelf_entries).to contain_exactly(entry)
    expect(user.group_memberships.find_by!(group:)).to be_active
    expect(group.reload.group_admin).to eq(user)
    expect(group).to be_active
  end

  it "rejects suspended and withdrawn users" do
    user.update!(suspended_at: Time.current)
    expect { described_class.new(user, actor:, public_reason: "Again").call! }.to raise_error(described_class::InvalidState)

    withdrawn = User.create!(name: "Withdrawn", email: "suspend-service-withdrawn@example.com", password: "password123!", withdrawn_at: Time.current)
    expect { described_class.new(withdrawn, actor:, public_reason: "Blocked").call! }.to raise_error(described_class::InvalidState)
  end

  it "rolls back suspended_at when the audit action is invalid" do
    expect {
      described_class.new(user, actor:, public_reason: "").call!
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(user.reload).not_to be_suspended
    expect(ModerationAction.where(target: user)).to be_empty
  end
end
