class CreateBookActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :book_activities do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.references :bookshelf_entry, foreign_key: true
      t.string :action, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :book_activities, :action
    add_index :book_activities, :created_at
  end
end
