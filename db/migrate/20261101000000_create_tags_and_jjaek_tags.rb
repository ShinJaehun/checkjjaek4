class CreateTagsAndJjaekTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :tags, :name, unique: true

    create_table :jjaek_tags do |t|
      t.references :jjaek, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :jjaek_tags, %i[jjaek_id tag_id], unique: true
  end
end
