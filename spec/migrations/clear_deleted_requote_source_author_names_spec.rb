require "rails_helper"
require Rails.root.join("db/migrate/20261128000000_clear_deleted_requote_source_author_names")

RSpec.describe ClearDeletedRequoteSourceAuthorNames do
  it "clears only source names on detached records marked as deleted" do
    author = User.create!(name: "Original", email: "source-cleanup@example.com", password: "password123!")
    source = author.jjaeks.create!(content: "Source")
    detached = author.jjaeks.create!(content: "Personal opinion", visibility: :private_jjaek,
      quoted_source_deleted_at: Time.current, quoted_source_kind: "book", quoted_source_author_name: "Old name")
    still_linked = author.jjaeks.create!(content: "Linked opinion", quoted_jjaek: source)
    still_linked.update_columns(quoted_source_deleted_at: Time.current, quoted_source_author_name: "Old name")
    unmarked = author.jjaeks.create!(content: "Regular post", quoted_source_author_name: "Old name")

    original = detached.reload.attributes
    unchanged = [ still_linked, unmarked ].map { |post| post.reload.attributes }
    migration = described_class.new
    migration.suppress_messages { migration.migrate(:up) }

    expect(detached.reload.attributes).to eq(original.merge("quoted_source_author_name" => nil))
    expect([ still_linked, unmarked ].map { |post| post.reload.attributes }).to eq(unchanged)
    expect {
      migration.suppress_messages do
        migration.migrate(:down)
      end
    }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
