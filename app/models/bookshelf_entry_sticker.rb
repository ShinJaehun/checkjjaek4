class BookshelfEntrySticker < ApplicationRecord
  belongs_to :bookshelf_entry
  belongs_to :sticker_definition

  validates :sticker_definition_id, uniqueness: { scope: :bookshelf_entry_id }
end
