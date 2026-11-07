require "rails_helper"
require Rails.root.join("db/migrate/20261103000000_add_recommendations_to_jjaeks")
require Rails.root.join("db/migrate/20261106000000_generalize_jjaek_book_attachments")
require Rails.root.join("db/migrate/20261107000000_rename_jjaek_recommendations_to_book_attachments")

RSpec.describe RenameJjaekRecommendationsToBookAttachments do
  around do |example|
    connection = ActiveRecord::Base.connection
    original_path = connection.schema_search_path
    schema = "attachment_rename_#{SecureRandom.hex(6)}"
    connection.create_schema(schema)
    connection.schema_search_path = schema
    described_class.new.suppress_messages { example.run }
  ensure
    connection.schema_search_path = original_path
    connection.execute("DROP SCHEMA IF EXISTS #{connection.quote_column_name(schema)} CASCADE")
    connection.schema_cache.clear!
  end

  it "preserves legacy and ordered attachment rows and constraints through rename and rollback" do
    connection = ActiveRecord::Base.connection
    # Build the pre-recommendation schema, then run the unchanged historical migrations.
    connection.create_table(:books)
    connection.create_table(:jjaeks) do |table|
      table.bigint :book_id
      table.bigint :quoted_jjaek_id
      table.datetime :quoted_source_deleted_at
      table.bigint :target_user_id
      table.timestamps
    end
    connection.execute("INSERT INTO books (id) VALUES (11), (12)")
    connection.execute(<<~SQL)
      INSERT INTO jjaeks (id, book_id, created_at, updated_at)
      VALUES (21, 11, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
             (22, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    AddRecommendationsToJjaeks.new.migrate(:up)
    connection.execute("UPDATE jjaeks SET recommendation = TRUE WHERE id = 22")
    connection.execute(<<~SQL)
      INSERT INTO jjaek_recommendations (jjaek_id, book_id, position, created_at, updated_at)
      VALUES (22, 12, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
             (22, 11, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    GeneralizeJjaekBookAttachments.new.migrate(:up)
    original = connection.select_all("SELECT * FROM jjaek_recommendations ORDER BY jjaek_id, position").to_a
    expect(original.map { |row| [ row["jjaek_id"], row["book_id"], row["position"] ] }).to eq([ [ 21, 11, 0 ], [ 22, 12, 0 ], [ 22, 11, 1 ] ])

    migration = described_class.new
    migration.migrate(:up)

    expect(connection.select_all("SELECT * FROM jjaek_book_attachments ORDER BY jjaek_id, position").to_a).to eq(original)
    expect(connection.foreign_keys(:jjaek_book_attachments).map(&:to_table)).to match_array(%w[books jjaeks])
    indexes = connection.indexes(:jjaek_book_attachments)
    expect(indexes.map(&:name)).to match_array(%w[
      index_jjaek_book_attachments_on_book_id
      index_jjaek_book_attachments_on_jjaek_id
      index_jjaek_book_attachments_on_jjaek_id_and_book_id
      index_jjaek_book_attachments_on_jjaek_id_and_position
    ])
    expect(indexes.select(&:unique).map(&:columns)).to match_array([ %w[jjaek_id book_id], %w[jjaek_id position] ])
    expect(connection.check_constraints(:jjaek_book_attachments).map(&:name)).to eq([ "jjaek_book_attachment_position" ])

    migration.migrate(:down)
    expect(connection.select_all("SELECT * FROM jjaek_recommendations ORDER BY jjaek_id, position").to_a).to eq(original)
    expect(connection.check_constraints(:jjaek_recommendations).map(&:name)).to eq([ "jjaek_recommendation_position" ])
  end
end
