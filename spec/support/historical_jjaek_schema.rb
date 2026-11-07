require Rails.root.join("db/migrate/20261103000000_add_recommendations_to_jjaeks")
require Rails.root.join("db/migrate/20261106000000_generalize_jjaek_book_attachments")

# Historical migrations use SQL records in an isolated schema, never today's
# application model with columns that did not exist (or have since been removed).
module HistoricalJjaekSchema
  def with_historical_jjaek_schema
    connection = ActiveRecord::Base.connection
    original_path = connection.schema_search_path
    source_schema = connection.select_value("SELECT current_schema()")
    schema = "historical_jjaeks_#{SecureRandom.hex(6)}"
    connection.create_schema(schema)
    connection.schema_search_path = "#{schema}, #{original_path}"
    tables = %w[books jjaeks comments likes notifications]
    tables.each do |table|
      source = connection.quote_table_name("#{source_schema}.#{table}")
      connection.execute("CREATE TABLE #{connection.quote_table_name(table)} (LIKE #{source} INCLUDING ALL)")
    end
    connection.remove_check_constraint(:jjaeks, name: "jjaek_legacy_source_kind")
    connection.remove_column(:jjaeks, :legacy_source_kind)
    connection.add_reference(:jjaeks, :book, foreign_key: true)
    GeneralizeJjaekBookAttachments.new.suppress_messages do
      AddRecommendationsToJjaeks.new.migrate(:up)
      GeneralizeJjaekBookAttachments.new.migrate(:up)
      records = (tables + %w[jjaek_recommendations]).to_h do |table|
        record = Class.new(ActiveRecord::Base) { self.table_name = "#{schema}.#{table}" }
        [table.to_sym, record]
      end
      yield records
    end
  ensure
    connection.schema_search_path = original_path
    connection.execute("DROP SCHEMA IF EXISTS #{connection.quote_column_name(schema)} CASCADE")
    connection.schema_cache.clear!
  end
end

RSpec.configure { |config| config.include HistoricalJjaekSchema }
