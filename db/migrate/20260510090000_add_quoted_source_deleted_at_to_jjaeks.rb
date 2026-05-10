class AddQuotedSourceDeletedAtToJjaeks < ActiveRecord::Migration[8.1]
  def change
    add_column :jjaeks, :quoted_source_deleted_at, :datetime
    add_index :jjaeks, :quoted_source_deleted_at
  end
end
