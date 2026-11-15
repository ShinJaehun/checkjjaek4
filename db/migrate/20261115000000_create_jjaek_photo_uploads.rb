class CreateJjaekPhotoUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :jjaek_photo_uploads do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :blob, foreign_key: { to_table: :active_storage_blobs, on_delete: :nullify }, index: { unique: true }
      t.date :uploaded_on, null: false
      t.bigint :byte_size, null: false
      t.timestamps
    end
    add_index :jjaek_photo_uploads, [ :user_id, :uploaded_on ]
  end
end
