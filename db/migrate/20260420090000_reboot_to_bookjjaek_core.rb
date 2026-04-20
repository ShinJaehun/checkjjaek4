class RebootToBookjjaekCore < ActiveRecord::Migration[8.1]
  def change
    drop_table :comments
    drop_table :likes
    drop_table :posts

    create_table :books do |t|
      t.string :title, null: false
      t.string :authors_text
      t.string :publisher
      t.string :thumbnail
      t.string :isbn
      t.text :description
      t.string :external_url
      t.timestamps
    end
    add_index :books, :isbn
    add_index :books, :external_url

    create_table :bookshelf_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :bookshelf_entries, [ :user_id, :book_id ], unique: true

    create_table :sticker_definitions do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :sticker_definitions, :key, unique: true

    create_table :bookshelf_entry_stickers do |t|
      t.references :bookshelf_entry, null: false, foreign_key: true
      t.references :sticker_definition, null: false, foreign_key: true
      t.timestamps
    end
    add_index :bookshelf_entry_stickers, [ :bookshelf_entry_id, :sticker_definition_id ],
              unique: true,
              name: "index_bookshelf_entry_stickers_on_entry_and_sticker"

    create_table :book_friendships do |t|
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.references :addressee, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :book_friendships, [ :requester_id, :addressee_id ], unique: true

    create_table :jjaeks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.references :quoted_jjaek, foreign_key: { to_table: :jjaeks }
      t.text :content, null: false
      t.integer :visibility, null: false, default: 0
      t.timestamps
    end
    add_index :jjaeks, :created_at

    create_table :comments do |t|
      t.references :jjaek, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false
      t.timestamps
    end

    create_table :likes do |t|
      t.references :jjaek, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :likes, [ :user_id, :jjaek_id ], unique: true
  end
end
