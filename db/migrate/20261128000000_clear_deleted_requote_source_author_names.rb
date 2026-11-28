class ClearDeletedRequoteSourceAuthorNames < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE jjaeks
      SET quoted_source_author_name = NULL
      WHERE quoted_jjaek_id IS NULL
        AND quoted_source_deleted_at IS NOT NULL
        AND quoted_source_author_name IS NOT NULL
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Deleted quote source author names cannot be recovered"
  end
end
