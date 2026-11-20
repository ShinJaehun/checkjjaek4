class StickerDefinition < ApplicationRecord
  has_many :user_book_stickers, dependent: :destroy
  has_many :user_books, through: :user_book_stickers

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true

  scope :alphabetical, -> { order(:position, :id) }
end
