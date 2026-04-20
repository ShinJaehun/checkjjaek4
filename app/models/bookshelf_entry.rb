class BookshelfEntry < ApplicationRecord
  enum :status, { wish: 0, reading: 1, finished: 2 }, default: :wish, validate: true

  belongs_to :user
  belongs_to :book

  has_many :bookshelf_entry_stickers, dependent: :destroy
  has_many :sticker_definitions, through: :bookshelf_entry_stickers

  validates :book_id, uniqueness: { scope: :user_id }

  scope :recent_first, -> { includes(:book, :sticker_definitions).order(updated_at: :desc) }
end
