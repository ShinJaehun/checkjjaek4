class UserBook < ApplicationRecord
  enum :status, { wish: 0, reading: 1, finished: 2 }, validate: { allow_nil: true }

  belongs_to :user
  belongs_to :book

  has_many :book_notes, dependent: :destroy
  has_many :book_note_images
  has_many :user_book_stickers, dependent: :destroy
  has_many :sticker_definitions, through: :user_book_stickers
end
