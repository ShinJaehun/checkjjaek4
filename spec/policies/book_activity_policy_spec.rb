require "rails_helper"

RSpec.describe BookActivityPolicy do
  let(:viewer) { User.create!(name: "Viewer", email: "book-activity-viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:profile_user) { User.create!(name: "Profile User", email: "book-activity-profile@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "Policy Activity Book", authors_text: "Author") }
  let(:activity) { BookActivity.create!(user: profile_user, book:, action: :added_to_shelf) }

  it "allows a user to see their own book activity" do
    own_activity = BookActivity.create!(user: viewer, book:, action: :added_to_shelf)

    expect(described_class.new(viewer, own_activity).show?).to be(true)
    expect(Pundit.policy_scope!(viewer, BookActivity)).to include(own_activity)
  end

  it "allows an accepted book friend to see book activity" do
    BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)

    expect(described_class.new(viewer, activity).show?).to be(true)
    expect(Pundit.policy_scope!(viewer, BookActivity)).to include(activity)
  end

  it "does not allow a stranger to see book activity" do
    expect(described_class.new(viewer, activity).show?).to be(false)
    expect(Pundit.policy_scope!(viewer, BookActivity)).not_to include(activity)
  end

  it "does not allow a follow-only user to see book activity" do
    viewer.active_follows.create!(followee: profile_user)

    expect(described_class.new(viewer, activity).show?).to be(false)
    expect(Pundit.policy_scope!(viewer, BookActivity)).not_to include(activity)
  end
end
