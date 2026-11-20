class UserBookSticker < ApplicationRecord
  belongs_to :user_book
  belongs_to :sticker_definition

  validates :sticker_definition_id, uniqueness: { scope: :user_book_id }
end
