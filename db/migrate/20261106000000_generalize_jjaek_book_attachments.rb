class GeneralizeJjaekBookAttachments < ActiveRecord::Migration[8.1]
  def up
    # AddRecommendationsToJjaeks runs first, including on installations which
    # have never deployed recommendations. Do not rewrite that migration.
    add_column :jjaeks, :book_attachments_migrated, :boolean, default: false, null: false
    remove_check_constraint :jjaeks, name: "jjaek_recommendation_context"
    backfill_book_attachments
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Unified attachments cannot be represented by the old application"
  end

  # Only unconverted rows are eligible. A deliberate empty list is never
  # repopulated from book_id, even when this operation is repeated.
  def backfill_book_attachments
    transaction do
      execute "LOCK TABLE jjaeks, jjaek_recommendations IN SHARE ROW EXCLUSIVE MODE"
      invalid_id = select_value(<<~SQL)
        SELECT j.id FROM jjaeks j
        WHERE NOT j.book_attachments_migrated AND (
          (SELECT COUNT(*) FROM jjaek_recommendations r WHERE r.jjaek_id = j.id) > 5
          OR (j.book_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM jjaek_recommendations r
            WHERE r.jjaek_id = j.id AND r.book_id <> j.book_id
          ))
        ) LIMIT 1
      SQL
      raise "Conflicting book attachments on Jjaek #{invalid_id}; no data was truncated or merged" if invalid_id

      execute <<~SQL
        INSERT INTO jjaek_recommendations (jjaek_id, book_id, position, created_at, updated_at)
        SELECT j.id, j.book_id, 0, j.created_at, j.updated_at FROM jjaeks j
        WHERE NOT j.book_attachments_migrated AND j.book_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM jjaek_recommendations r WHERE r.jjaek_id = j.id)
      SQL
      execute "UPDATE jjaeks SET book_attachments_migrated = TRUE WHERE NOT book_attachments_migrated"
    end
  end
end
