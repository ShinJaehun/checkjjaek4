class AddHiddenAtToJjaeks < ActiveRecord::Migration[8.1]
  def change
    add_column :jjaeks, :hidden_at, :datetime
    add_index :jjaeks, :hidden_at
  end
end
