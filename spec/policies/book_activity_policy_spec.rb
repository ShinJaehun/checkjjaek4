require "rails_helper"

RSpec.describe BookActivityPolicy do
  let(:viewer) { User.create!(name: "Viewer", email: "book-activity-viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:profile_user) { User.create!(name: "Profile User", email: "book-activity-profile@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "Policy Activity Book", authors_text: "Author") }
  let(:activity) { BookActivity.create!(user: profile_user, book:, bookshelf_entry: profile_user.bookshelf_entries.find_or_create_by!(book: book), action: :added_to_shelf) }

  it "allows a user to see their own book activity" do
    own_activity = BookActivity.create!(user: viewer, book:, bookshelf_entry: viewer.bookshelf_entries.find_or_create_by!(book: book), action: :added_to_shelf)

    expect(described_class.new(viewer, own_activity).show?).to be(true)
    expect(Pundit.policy_scope!(viewer, BookActivity)).to include(own_activity)
    expect(described_class::FeedScope.new(viewer, BookActivity.all).resolve).to include(own_activity)
  end

  it "allows an accepted book friend to see book activity" do
    BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)

    expect(described_class.new(viewer, activity).show?).to be(true)
    expect(Pundit.policy_scope!(viewer, BookActivity)).to include(activity)
    expect(described_class::ProfileScope.new(viewer, profile_user.book_activities).resolve).to include(activity)
    expect(described_class::FeedScope.new(viewer, BookActivity.all).resolve).not_to include(activity)
  end

  it "includes an accepted book friend's activity in the feed when followed" do
    BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
    viewer.active_follows.create!(followee: profile_user)

    expect(described_class::FeedScope.new(viewer, BookActivity.all).resolve).to include(activity)
  end

  it "does not allow a stranger to see book activity" do
    expect(described_class.new(viewer, activity).show?).to be(false)
    expect(Pundit.policy_scope!(viewer, BookActivity)).not_to include(activity)
    expect(described_class::FeedScope.new(viewer, BookActivity.all).resolve).not_to include(activity)
  end

  it "does not allow a follow-only user to see book activity" do
    viewer.active_follows.create!(followee: profile_user)

    expect(described_class.new(viewer, activity).show?).to be(false)
    expect(Pundit.policy_scope!(viewer, BookActivity)).not_to include(activity)
    expect(described_class::FeedScope.new(viewer, BookActivity.all).resolve).not_to include(activity)
  end

  it "includes the investigated user's activity in profile scope for a global admin" do
    global_admin = User.create!(name: "Global admin", email: "book-activity-global-admin@example.com", password: "password123!", global_admin: true)

    expect(described_class::ProfileScope.new(global_admin, profile_user.book_activities).resolve).to include(activity)
    expect(described_class::Scope.new(global_admin, BookActivity.all).resolve).not_to include(activity)
    expect(described_class::FeedScope.new(global_admin, BookActivity.all).resolve).not_to include(activity)
  end

  it "keeps a stranger's profile activity hidden from an unrelated user" do
    expect(described_class::ProfileScope.new(viewer, profile_user.book_activities).resolve).not_to include(activity)
  end
  it "filters every legacy change action and orphaned additions from all scopes" do
    entry = activity.bookshelf_entry
    changes = (BookActivity.actions.keys - [ "added_to_shelf" ]).map do |action|
      BookActivity.create!(user: profile_user, book: book, bookshelf_entry: entry, action: action)
    end
    orphan = BookActivity.create!(user: profile_user, book: book, action: :added_to_shelf)
    BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
    viewer.active_follows.create!(followee: profile_user)

    [ described_class::Scope, described_class::FeedScope, described_class::ProfileScope ].each do |scope_class|
      expect(scope_class.new(viewer, BookActivity.all).resolve).to include(activity)
      expect(scope_class.new(viewer, BookActivity.all).resolve).not_to include(*changes, orphan)
    end
    (changes + [ orphan ]).each { |record| expect(described_class.new(profile_user, record).show?).to be(false) }
  end

  it "uses current bookshelf visibility without widening the relationship boundary" do
    entry = activity.bookshelf_entry
    shelf = profile_user.bookshelves.create!(name: "Activity shelf", visibility: :public)
    entry.move_to_bookshelf!(shelf)
    BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
    viewer.active_follows.create!(followee: profile_user)

    [ :public, :book_friends, :private ].each do |visibility|
      shelf.update!(visibility: visibility)
      activity.reload
      visible = visibility != :private
      expect(described_class.new(viewer, activity).show?).to eq(visible)
      [ described_class::Scope, described_class::FeedScope, described_class::ProfileScope ].each do |scope_class|
        expect(scope_class.new(viewer, BookActivity.all).resolve.exists?(activity.id)).to eq(visible)
        expect(scope_class.new(profile_user, BookActivity.all).resolve).to include(activity)
      end
    end
  end

  it "hides an old addition after moving the entry into a private bookshelf" do
    BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)
    entry = activity.bookshelf_entry
    expect(described_class::Scope.new(viewer, BookActivity.all).resolve).to include(activity)

    private_shelf = profile_user.bookshelves.create!(name: "Private destination", visibility: :private)
    entry.move_to_bookshelf!(private_shelf)

    expect(described_class::Scope.new(viewer, BookActivity.all).resolve).not_to include(activity)
    expect(described_class.new(viewer, activity.reload).show?).to be(false)
  end
end
