# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_23_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "book_friendships", force: :cascade do |t|
    t.bigint "addressee_id", null: false
    t.datetime "created_at", null: false
    t.bigint "requester_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["addressee_id"], name: "index_book_friendships_on_addressee_id"
    t.index ["requester_id", "addressee_id"], name: "index_book_friendships_on_requester_id_and_addressee_id", unique: true
    t.index ["requester_id"], name: "index_book_friendships_on_requester_id"
  end

  create_table "books", force: :cascade do |t|
    t.string "authors_text"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "external_url"
    t.string "isbn"
    t.string "publisher"
    t.string "thumbnail"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["external_url"], name: "index_books_on_external_url"
    t.index ["isbn"], name: "index_books_on_isbn"
  end

  create_table "bookshelf_entries", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.datetime "created_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["book_id"], name: "index_bookshelf_entries_on_book_id"
    t.index ["user_id", "book_id"], name: "index_bookshelf_entries_on_user_id_and_book_id", unique: true
    t.index ["user_id"], name: "index_bookshelf_entries_on_user_id"
  end

  create_table "bookshelf_entry_stickers", force: :cascade do |t|
    t.bigint "bookshelf_entry_id", null: false
    t.datetime "created_at", null: false
    t.bigint "sticker_definition_id", null: false
    t.datetime "updated_at", null: false
    t.index ["bookshelf_entry_id", "sticker_definition_id"], name: "index_bookshelf_entry_stickers_on_entry_and_sticker", unique: true
    t.index ["bookshelf_entry_id"], name: "index_bookshelf_entry_stickers_on_bookshelf_entry_id"
    t.index ["sticker_definition_id"], name: "index_bookshelf_entry_stickers_on_sticker_definition_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "jjaek_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["jjaek_id"], name: "index_comments_on_jjaek_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "followee_id", null: false
    t.bigint "follower_id", null: false
    t.datetime "updated_at", null: false
    t.index ["followee_id"], name: "index_follows_on_followee_id"
    t.index ["follower_id", "followee_id"], name: "index_follows_on_follower_id_and_followee_id", unique: true
    t.index ["follower_id"], name: "index_follows_on_follower_id"
  end

  create_table "jjaeks", force: :cascade do |t|
    t.bigint "book_id"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "quoted_jjaek_id"
    t.bigint "target_user_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "visibility", default: 0, null: false
    t.index ["book_id"], name: "index_jjaeks_on_book_id"
    t.index ["created_at"], name: "index_jjaeks_on_created_at"
    t.index ["quoted_jjaek_id"], name: "index_jjaeks_on_quoted_jjaek_id"
    t.index ["target_user_id"], name: "index_jjaeks_on_target_user_id"
    t.index ["user_id"], name: "index_jjaeks_on_user_id"
  end

  create_table "likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "jjaek_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["jjaek_id"], name: "index_likes_on_jjaek_id"
    t.index ["user_id", "jjaek_id"], name: "index_likes_on_user_id_and_jjaek_id", unique: true
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "sticker_definitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_sticker_definitions_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "book_friendships", "users", column: "addressee_id"
  add_foreign_key "book_friendships", "users", column: "requester_id"
  add_foreign_key "bookshelf_entries", "books"
  add_foreign_key "bookshelf_entries", "users"
  add_foreign_key "bookshelf_entry_stickers", "bookshelf_entries"
  add_foreign_key "bookshelf_entry_stickers", "sticker_definitions"
  add_foreign_key "comments", "jjaeks"
  add_foreign_key "comments", "users"
  add_foreign_key "follows", "users", column: "followee_id"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "jjaeks", "books"
  add_foreign_key "jjaeks", "jjaeks", column: "quoted_jjaek_id"
  add_foreign_key "jjaeks", "users"
  add_foreign_key "jjaeks", "users", column: "target_user_id"
  add_foreign_key "likes", "jjaeks"
  add_foreign_key "likes", "users"
end
