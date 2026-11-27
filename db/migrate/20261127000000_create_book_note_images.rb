class CreateBookNoteImages < ActiveRecord::Migration[8.1]
  def change
    create_table :book_note_images do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :user_book, foreign_key: { on_delete: :nullify }
      t.references :book_note, foreign_key: { on_delete: :nullify }
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }, index: { unique: true }
      t.string :state, null: false, default: "uploading"
      t.datetime :expires_at
      t.timestamps

      t.check_constraint "state IN ('uploading', 'temporary', 'attached', 'purging')", name: "book_note_images_valid_state"
      t.check_constraint "book_note_id IS NULL OR state = 'attached'", name: "book_note_images_valid_note_link"
      t.check_constraint "(state = 'temporary') = (expires_at IS NOT NULL)", name: "book_note_images_valid_expiry"
    end
  end
end
