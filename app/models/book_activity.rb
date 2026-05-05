class BookActivity < ApplicationRecord
  enum :action, {
    added_to_shelf: "added_to_shelf",
    status_changed: "status_changed",
    status_cleared: "status_cleared",
    sticker_added: "sticker_added",
    sticker_removed: "sticker_removed",
    bookshelf_entry_updated: "bookshelf_entry_updated"
  }, validate: true

  belongs_to :user
  belongs_to :book
  belongs_to :bookshelf_entry, optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
