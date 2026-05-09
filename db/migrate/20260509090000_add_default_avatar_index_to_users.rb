class AddDefaultAvatarIndexToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :default_avatar_index, :integer
  end
end
