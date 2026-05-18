class BookshelfEntry < ApplicationRecord
  PROFILE_SORTS = %w[recent manual title author status].freeze

  enum :status, { wish: 0, reading: 1, finished: 2 }, validate: { allow_nil: true }

  belongs_to :user
  belongs_to :book
  belongs_to :bookshelf

  has_many :bookshelf_entry_stickers, dependent: :destroy
  has_many :sticker_definitions, through: :bookshelf_entry_stickers

  before_validation :assign_default_bookshelf
  before_validation :assign_position, on: :create

  validates :book_id, uniqueness: { scope: :user_id }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :bookshelf_belongs_to_user

  scope :recent_first, -> { includes(:book, :sticker_definitions).order(updated_at: :desc) }
  scope :profile_sorted, ->(sort) {
    case sort
    when "manual"
      includes(:book, :sticker_definitions).order(position: :asc, id: :asc)
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

  def move_to_bookshelf!(target_bookshelf, before_entry: nil)
    validate_before_entry_for_move!(target_bookshelf, before_entry) if before_entry
    return true if bookshelf_id == target_bookshelf.id && before_entry.blank?

    self.class.transaction do
      target_entries = target_bookshelf.bookshelf_entries.where.not(id: id).order(:position, :id).to_a
      insert_at = before_entry ? target_entries.index { |entry| entry.id == before_entry.id } : target_entries.size
      target_entries.insert(insert_at, self)

      target_entries.each_with_index do |entry, index|
        entry.update!(bookshelf: target_bookshelf, position: index + 1)
      end
    end
  end

  def self.reorder_within!(bookshelf:, ordered_ids:)
    ids = Array(ordered_ids).map(&:to_i)
    current_ids = bookshelf.bookshelf_entries.order(:id).pluck(:id)
    raise ActiveRecord::RecordInvalid, bookshelf unless ids.sort == current_ids.sort

    transaction do
      ids.each_with_index do |id, index|
        bookshelf.bookshelf_entries.find(id).update!(position: index + 1)
      end
    end
  end

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

  def assign_position
    return if position.present? || bookshelf.blank?

    self.position = next_position_in(bookshelf)
  end

  def next_position_in(target_bookshelf)
    target_bookshelf.bookshelf_entries.where.not(id: id).maximum(:position).to_i + 1
  end

  def validate_before_entry_for_move!(target_bookshelf, before_entry)
    return if before_entry.user_id == user_id && before_entry.bookshelf_id == target_bookshelf.id

    errors.add(:base, :invalid)
    raise ActiveRecord::RecordInvalid.new(self)
  end
end
