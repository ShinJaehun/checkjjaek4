class BookshelfEntry < ApplicationRecord
  PROFILE_SORTS = %w[recent manual title author status].freeze

  belongs_to :user
  belongs_to :book
  belongs_to :bookshelf
  belongs_to :user_book

  # The foreign key clears the placement when it is removed and retains the activity rows.
  has_many :book_activities

  before_validation :assign_user_book, on: :create
  before_validation :assign_default_bookshelf
  before_validation :assign_position, on: :create

  validates :book_id, uniqueness: { scope: :user_id }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :bookshelf_belongs_to_user
  validate :user_book_matches_entry, if: -> { new_record? || user_book_id_changed? || user_id_changed? || book_id_changed? }

  scope :with_reading_record, -> { includes(:book, user_book: :sticker_definitions) }
  scope :recent_first, -> { with_reading_record.order(bookshelf_entries: { updated_at: :desc }) }
  scope :profile_sorted, ->(sort) {
    case sort
    when "manual"
      with_reading_record.order(position: :asc, id: :asc)
    when "title"
      joins(:book).with_reading_record.order(books: { title: :asc }, id: :asc)
    when "author"
      joins(:book).with_reading_record.order(books: { authors_text: :asc }, id: :asc)
    when "status"
      joins(:user_book).with_reading_record.order(user_books: { status: :asc }, bookshelf_entries: { updated_at: :desc, id: :asc })
    else
      recent_first
    end
  }

  def move_to_bookshelf!(target_bookshelf, before_entry: nil)
    return true if bookshelf_id == target_bookshelf.id && before_entry.blank?

    self.class.transaction do
      target_entries = target_bookshelf.bookshelf_entries.where.not(id: id).order(:position, :id).to_a
      insert_at = if before_entry
        target_entries.index { |entry| entry.id == before_entry.id && entry.user_id == user_id }
      else
        target_entries.size
      end
      unless insert_at
        errors.add(:base, :invalid)
        raise ActiveRecord::RecordInvalid.new(self)
      end
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

  def self.bulk_move_to_bookshelf!(entries:, target_bookshelf:)
    transaction do
      next_position = target_bookshelf.bookshelf_entries.maximum(:position).to_i
      moved_count = 0

      entries.each do |entry|
        next if entry.bookshelf_id == target_bookshelf.id

        next_position += 1
        entry.update!(bookshelf: target_bookshelf, position: next_position)
        moved_count += 1
      end

      moved_count
    end
  end

  private

  def assign_user_book
    return if user_book.present? || user_id.blank? || book_id.blank?

    self.user_book = UserBook.find_or_initialize_by(user_id:, book_id:)
  end

  def user_book_matches_entry
    return if user_book.blank?
    return if user_book.user_id == user_id && user_book.book_id == book_id

    errors.add(:user_book, :invalid)
  end

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
end
