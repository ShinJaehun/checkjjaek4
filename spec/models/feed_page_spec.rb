require "rails_helper"

RSpec.describe FeedPage, type: :model do
  let(:user) { User.create!(name: "Feed reader", email: "feed-page@example.com", password: "password123!") }
  let(:time) { Time.zone.parse("2026-10-19 12:00:00.123456") }
  let(:book) { Book.create!(title: "Feed book", authors_text: "Author") }
  let(:entry) { user.bookshelf_entries.create!(book:) }

  def jjaek(index)
    user.jjaeks.create!(content: "Post #{index}", created_at: time)
  end

  def activity
    entry.book_activities.create!(user:, book:, action: :added_to_shelf, created_at: time)
  end

  it "uses descending IDs to paginate equal timestamps, including a short final page" do
    records = Array.new(45) { |index| jjaek(index) }.reverse
    first = described_class.new(jjaeks: user.jjaeks)
    second = described_class.new(jjaeks: user.jjaeks, cursor: first.next_cursor)
    last = described_class.new(jjaeks: user.jjaeks, cursor: second.next_cursor)

    expect(first.items).to eq(records.first(20))
    expect(second.items).to eq(records.slice(20, 20))
    expect(last.items).to eq(records.last(5))
    expect(last.next_cursor).to be_nil
  end

  it "puts Jjaeks before BookActivities at the same time and crosses the type boundary without gaps" do
    posts = Array.new(13) { |index| jjaek(index) }.reverse
    activities = Array.new(13) { activity }.reverse
    first = described_class.new(jjaeks: user.jjaeks, book_activities: user.book_activities)
    second = described_class.new(jjaeks: user.jjaeks, book_activities: user.book_activities, cursor: first.next_cursor)

    expect(first.items + second.items).to eq(posts + activities)
    expect(first.items.size).to eq(20)
    expect(second.next_cursor).to be_nil
  end

  it "sorts timestamps before type and ID in a mixed feed" do
    post = jjaek(1)
    newer_activity = activity
    newer_activity.update_columns(created_at: time + 1.second)

    expect(described_class.new(jjaeks: user.jjaeks, book_activities: user.book_activities).items).to eq([ newer_activity, post ])
  end

  it "includes all tied BookActivities after a cursor ending on a Jjaek" do
    posts = Array.new(21) { |index| jjaek(index) }.reverse
    activities = Array.new(2) { activity }.reverse
    first = described_class.new(jjaeks: user.jjaeks, book_activities: user.book_activities)
    second = described_class.new(jjaeks: user.jjaeks, book_activities: user.book_activities, cursor: first.next_cursor)

    expect(first.items + second.items).to eq(posts + activities)
    expect(second.next_cursor).to be_nil
  end

  it "keeps the cursor boundary after deletion and excludes newly inserted posts above it" do
    posts = Array.new(45) { |index| jjaek(index) }.reverse
    first = described_class.new(jjaeks: user.jjaeks)
    first.items.last.destroy!
    posts[22].destroy!
    inserted = jjaek("new")
    second = described_class.new(jjaeks: user.jjaeks, cursor: first.next_cursor)
    last = described_class.new(jjaeks: user.jjaeks, cursor: second.next_cursor)

    remaining = second.items + last.items
    expect(remaining).to eq(posts.drop(20) - [ posts[22] ])
    expect(remaining & first.items).to be_empty
    expect(remaining).not_to include(inserted)
  end

  it "returns no next cursor for empty results or exactly twenty results" do
    expect(described_class.new(jjaeks: user.jjaeks).items).to be_empty
    expect(described_class.new(jjaeks: user.jjaeks).next_cursor).to be_nil
    20.times { |index| jjaek(index) }
    expect(described_class.new(jjaeks: user.jjaeks).next_cursor).to be_nil
  end

  it "rejects modified and structurally invalid cursors" do
    21.times { |index| jjaek(index) }
    cursor = described_class.new(jjaeks: user.jjaeks).next_cursor
    malformed = Rails.application.message_verifier("feed-pagination").generate([ "not a date", 1, 1 ])

    [ "#{cursor}modified", malformed, "x" * 1025, [ cursor ], [], {} ].each do |invalid|
      expect { described_class.new(jjaeks: user.jjaeks, cursor: invalid) }.to raise_error(FeedPage::InvalidCursor)
    end
  end

  it "retrieves at most twenty-one records per source from the database" do
    30.times do |index|
      jjaek(index)
      activity
    end
    loaded = Hash.new(0)
    subscriber = ->(*args) { loaded[args.last[:class_name]] += args.last[:record_count] }

    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      page = described_class.new(jjaeks: user.jjaeks, book_activities: user.book_activities)
      expect(page.items.size).to eq(20)
    end
    expect(loaded.slice("Jjaek", "BookActivity")).to eq("Jjaek" => 21, "BookActivity" => 21)
  end
end
