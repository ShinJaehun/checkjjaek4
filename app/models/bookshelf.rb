class Bookshelf < ApplicationRecord
  DEFAULT_NAME = "내 책장"
  MAX_PER_USER = 20

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

  scope :default_first, -> { order(is_default: :desc, created_at: :asc, id: :asc) }

  before_destroy :prevent_default_bookshelf_destroy, unless: :user_being_destroyed?

  validates :name, presence: true
  validates :name, uniqueness: { scope: :user_id }
  validates :visibility, presence: true
  validates :is_default, uniqueness: { scope: :user_id }, if: :is_default?
  validate :default_bookshelf_name_cannot_change
  validate :default_bookshelf_visibility_cannot_change
  validate :default_bookshelf_flag_cannot_change_to_false
  validate :bookshelves_per_user_limit, on: :create

  private

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
