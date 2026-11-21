class CreateBookNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :action_text_rich_texts do |t|
      t.string :name, null: false
      t.text :body
      t.references :record, polymorphic: true, null: false, index: false
      t.timestamps

      t.index %i[record_type record_id name], unique: true, name: "index_action_text_rich_texts_uniqueness"
    end

    create_table :book_notes do |t|
      t.references :user_book, null: false, foreign_key: true, index: false
      t.text :title
      t.timestamps

      t.index %i[user_book_id created_at id]
    end
  end
end
