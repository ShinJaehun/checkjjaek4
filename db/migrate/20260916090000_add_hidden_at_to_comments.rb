class AddHiddenAtToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :hidden_at, :datetime
    add_index :comments, :hidden_at
  end
end
