class RemoveLegacyJjaekBookColumns < ActiveRecord::Migration[8.1]
  def up
    execute "LOCK TABLE jjaeks, jjaek_book_attachments IN SHARE ROW EXCLUSIVE MODE"
    invalid_id = select_value(<<~SQL)
      SELECT j.id FROM jjaeks j
      WHERE NOT j.book_attachments_migrated OR
        (j.book_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM jjaek_book_attachments a WHERE a.jjaek_id = j.id AND a.book_id = j.book_id
        )) LIMIT 1
    SQL
    raise "Unconverted book attachments on Jjaek #{invalid_id}" if invalid_id

    # Historical meaning only: never use this field to classify current posts.
    add_column :jjaeks, :legacy_source_kind, :string
    add_check_constraint :jjaeks, "legacy_source_kind IN ('book', 'recommendation')",
      name: "jjaek_legacy_source_kind"
    add_column :jjaek_book_attachments, :visible_on_tombstone, :boolean, default: false, null: false
    execute <<~SQL
      UPDATE jjaeks SET legacy_source_kind = CASE
        WHEN recommendation THEN 'recommendation' WHEN book_id IS NOT NULL THEN 'book' END
    SQL
    execute <<~SQL
      UPDATE jjaek_book_attachments a SET visible_on_tombstone = TRUE
      FROM jjaeks j WHERE a.jjaek_id = j.id AND a.book_id = j.book_id
    SQL
    remove_reference :jjaeks, :book, foreign_key: true
    remove_column :jjaeks, :recommendation
    remove_column :jjaeks, :book_attachments_migrated
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Legacy posting fields cannot represent unified attachments"
  end
end
