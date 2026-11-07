require "rails_helper"
require Rails.root.join("db/migrate/20261107000000_rename_jjaek_recommendations_to_book_attachments")
require Rails.root.join("db/migrate/20261108000000_remove_legacy_jjaek_book_columns")

RSpec.describe RemoveLegacyJjaekBookColumns do
  around { |example| with_historical_jjaek_schema { |tables| @tables = tables; example.run } }

  it "preserves rows, attachment order and historical snapshots while recording tombstone visibility" do
    posts = @tables.fetch(:jjaeks)
    links = @tables.fetch(:jjaek_recommendations)
    book = @tables.fetch(:books).create!(title: "Legacy tombstone book")
    other = @tables.fetch(:books).create!(title: "Modern private attachment")
    legacy = posts.create!(user_id: 1, content: "", book_id: book.id, deleted_at: Time.current)
    modern = posts.create!(user_id: 1, content: "", deleted_at: Time.current)
    recommended = posts.create!(user_id: 1, content: "Historical", recommendation: true)
    snapshot = posts.create!(user_id: 1, content: "Requote", quoted_source_kind: "book", quoted_source_deleted_at: Time.current, visibility: 2)
    links.create!(jjaek_id: modern.id, book_id: other.id, position: 0)
    links.create!(jjaek_id: recommended.id, book_id: other.id, position: 0)
    links.create!(jjaek_id: recommended.id, book_id: book.id, position: 1)
    GeneralizeJjaekBookAttachments.new.backfill_book_attachments
    original_posts = posts.order(:id).map(&:attributes)
    original_links = links.order(:id).map(&:attributes)
    RenameJjaekRecommendationsToBookAttachments.new.migrate(:up)
    links.table_name = links.table_name.sub("jjaek_recommendations", "jjaek_book_attachments")

    described_class.new.migrate(:up)

    posts.reset_column_information
    links.reset_column_information
    removed = %w[book_id recommendation book_attachments_migrated]
    expect(posts.column_names & removed).to be_empty
    expect(posts.order(:id).map { |record| record.attributes.except("legacy_source_kind") })
      .to eq(original_posts.map { |attributes| attributes.except(*removed) })
    expect(links.order(:id).map { |record| record.attributes.except("visible_on_tombstone") }).to eq(original_links)
    expect(links.where(visible_on_tombstone: true).pluck(:jjaek_id, :book_id)).to eq([ [ legacy.id, book.id ] ])
    expect(posts.find(recommended.id).legacy_source_kind).to eq("recommendation")
    expect(posts.find(snapshot.id).quoted_source_kind).to eq("book")
    expect(posts.find(modern.id).legacy_source_kind).to be_nil
  end

  it "stops before removing columns when a legacy attachment has not been converted" do
    post = @tables.fetch(:jjaeks).create!(user_id: 1, content: "Unconverted")
    RenameJjaekRecommendationsToBookAttachments.new.migrate(:up)

    expect { described_class.new.migrate(:up) }.to raise_error(/Unconverted book attachments/)
    post.class.reset_column_information
    expect(post.class.column_names).to include("book_id", "recommendation", "book_attachments_migrated")
    expect(post.reload.content).to eq("Unconverted")
  end
end
