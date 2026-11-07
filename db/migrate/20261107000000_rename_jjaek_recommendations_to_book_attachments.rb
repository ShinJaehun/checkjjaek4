class RenameJjaekRecommendationsToBookAttachments < ActiveRecord::Migration[8.1]
  def up
    # rename_table also renames the conventional indexes, primary key and sequence.
    # Existing rows and foreign keys remain attached to the same PostgreSQL table.
    rename_table :jjaek_recommendations, :jjaek_book_attachments
    execute <<~SQL
      ALTER TABLE jjaek_book_attachments
      RENAME CONSTRAINT jjaek_recommendation_position TO jjaek_book_attachment_position
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE jjaek_book_attachments
      RENAME CONSTRAINT jjaek_book_attachment_position TO jjaek_recommendation_position
    SQL
    rename_table :jjaek_book_attachments, :jjaek_recommendations
  end
end
