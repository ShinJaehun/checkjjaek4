class CreateGroupListHidings < ActiveRecord::Migration[8.1]
  def change
    create_table :group_list_hidings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: true
      t.timestamps
    end
    add_index :group_list_hidings, %i[user_id group_id], unique: true
  end
end
