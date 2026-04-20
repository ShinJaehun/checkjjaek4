class StickerDefinition < ApplicationRecord
  has_many :bookshelf_entry_stickers, dependent: :destroy
  has_many :bookshelf_entries, through: :bookshelf_entry_stickers

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true

  scope :alphabetical, -> { order(:position, :id) }
end
