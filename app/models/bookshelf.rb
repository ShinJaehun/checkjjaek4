class Bookshelf < ApplicationRecord
  DEFAULT_NAME = "내 책장"
  MAX_PER_USER = 20
  COLOR_KEYS = %w[stone red orange yellow green blue purple pink].freeze

  enum :visibility,
       {
         public: "public",
         book_friends: "book_friends",
         private: "private"
       },
       prefix: true,
       validate: true

  belongs_to :user

  has_many :bookshelf_entries, dependent: :restrict_with_error

  scope :default_first, -> { order(is_default: :desc, position: :asc, id: :asc) }

  before_validation :assign_position, on: :create
  before_destroy :prevent_default_bookshelf_destroy, unless: :user_being_destroyed?

  validates :name, presence: true
  validates :name, uniqueness: { scope: :user_id }
  validates :visibility, presence: true
  validates :color_key, presence: true, inclusion: { in: COLOR_KEYS }
  validates :is_default, uniqueness: { scope: :user_id }, if: :is_default?
  validate :default_bookshelf_name_cannot_change
  validate :default_bookshelf_visibility_cannot_change
  validate :default_bookshelf_color_key_must_be_stone
  validate :default_bookshelf_flag_cannot_change_to_false
  validate :bookshelves_per_user_limit, on: :create

  def move_up!
    swap_position_with(previous_regular_bookshelf)
  end

  def move_down!
    swap_position_with(next_regular_bookshelf)
  end

  private

  def assign_position
    self.position = 0 if is_default?
    return if is_default? || position.to_i.positive? || user.blank?

    self.position = user.bookshelves.where(is_default: false).maximum(:position).to_i + 1
  end

  def previous_regular_bookshelf
    user.bookshelves
      .where(is_default: false)
      .where("position < ? OR (position = ? AND id < ?)", position, position, id)
      .order(position: :desc, id: :desc)
      .first
  end

  def next_regular_bookshelf
    user.bookshelves
      .where(is_default: false)
      .where("position > ? OR (position = ? AND id > ?)", position, position, id)
      .order(position: :asc, id: :asc)
      .first
  end

  def swap_position_with(other_bookshelf)
    return true unless other_bookshelf

    self.class.transaction do
      current_position = position
      update!(position: other_bookshelf.position)
      other_bookshelf.update!(position: current_position)
    end
  end

  def prevent_default_bookshelf_destroy
    return unless is_default?

    errors.add(:base, :restrict_dependent_destroy, record: "default bookshelf")
    throw :abort
  end

  def user_being_destroyed?
    destroyed_by_association&.active_record == User
  end

  def default_bookshelf_name_cannot_change
    return unless is_default?
    return unless will_save_change_to_name?
    return if new_record?

    errors.add(:name, :invalid)
  end

  def default_bookshelf_visibility_cannot_change
    return unless is_default?
    return unless will_save_change_to_visibility?
    return if new_record?

    errors.add(:visibility, :invalid)
  end

  def default_bookshelf_color_key_must_be_stone
    return unless is_default?
    return if color_key == "stone"

    errors.add(:color_key, :invalid)
  end

  def default_bookshelf_flag_cannot_change_to_false
    return unless will_save_change_to_is_default?(from: true, to: false)

    errors.add(:is_default, :invalid)
  end

  def bookshelves_per_user_limit
    return unless user
    return if user.bookshelves.count < MAX_PER_USER

    errors.add(:base, :too_many_bookshelves, count: MAX_PER_USER)
  end
end
