class AddQuotedSourceSnapshotToJjaeks < ActiveRecord::Migration[8.1]
  def change
    add_column :jjaeks, :quoted_source_author_name, :string
    add_column :jjaeks, :quoted_source_kind, :string
  end
end
