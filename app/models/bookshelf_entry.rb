class BookshelfEntry < ApplicationRecord
  PROFILE_SORTS = %w[recent title author status].freeze

  enum :status, { wish: 0, reading: 1, finished: 2 }, validate: { allow_nil: true }

  belongs_to :user
  belongs_to :book
  belongs_to :bookshelf

  has_many :bookshelf_entry_stickers, dependent: :destroy
  has_many :sticker_definitions, through: :bookshelf_entry_stickers

  before_validation :assign_default_bookshelf

  validates :book_id, uniqueness: { scope: :user_id }
  validate :bookshelf_belongs_to_user

  scope :recent_first, -> { includes(:book, :sticker_definitions).order(updated_at: :desc) }
  scope :profile_sorted, ->(sort) {
    case sort
    when "title"
      joins(:book).includes(:book, :sticker_definitions).order(books: { title: :asc }, id: :asc)
    when "author"
      joins(:book).includes(:book, :sticker_definitions).order(books: { authors_text: :asc }, id: :asc)
    when "status"
      includes(:book, :sticker_definitions).order(status: :asc, updated_at: :desc, id: :asc)
    else
      recent_first
    end
  }

  private

  def assign_default_bookshelf
    return if bookshelf.present?
    return unless user&.persisted?

    self.bookshelf = user.default_bookshelf || user.create_default_bookshelf!
  end

  def bookshelf_belongs_to_user
    return if bookshelf.blank? || user_id.blank?
    return if bookshelf.user_id == user_id

    errors.add(:bookshelf, :invalid)
  end
end
