class AddLifecycleTimestampsToJjaeks < ActiveRecord::Migration[8.1]
  def change
    add_column :jjaeks, :content_edited_at, :datetime
    add_column :jjaeks, :deleted_at, :datetime
  end
end
