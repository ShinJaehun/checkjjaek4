require "rails_helper"

RSpec.describe BookActivity, type: :model do
  let(:user) { User.create!(name: "Activity User", email: "activity-user@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "Activity Book", authors_text: "Author") }
  let(:bookshelf_entry) { user.bookshelf_entries.create!(book:) }

  it "requires user, book, and action" do
    activity = described_class.new

    expect(activity).not_to be_valid
    expect(activity.errors[:user]).to be_present
    expect(activity.errors[:book]).to be_present
    expect(activity.errors[:action]).to be_present
  end

  it "does not allow an unknown action" do
    activity = described_class.new(user:, book:, action: "unknown_action")

    expect(activity).not_to be_valid
    expect(activity.errors[:action]).to be_present
  end

  it "orders recent activities first" do
    older = described_class.create!(user:, book:, action: :added_to_shelf, created_at: 2.days.ago)
    newer = described_class.create!(user:, book:, action: :status_changed, created_at: 1.day.ago)

    expect(described_class.recent).to eq([ newer, older ])
  end

  it "can be created without explicit metadata" do
    activity = described_class.create!(user:, book:, action: :added_to_shelf)

    expect(activity.metadata).to eq({})
  end

  it "can reference a bookshelf entry when the activity is tied to a current shelf item" do
    activity = described_class.create!(user:, book:, bookshelf_entry:, action: :status_changed)

    expect(activity.bookshelf_entry).to eq(bookshelf_entry)
  end

  it "can be created without a bookshelf entry" do
    activity = described_class.create!(user:, book:, action: :added_to_shelf)

    expect(activity.bookshelf_entry).to be_nil
  end
end
