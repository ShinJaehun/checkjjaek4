class Bookshelf < ApplicationRecord
  DEFAULT_NAME = "내 책장"

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

  validates :name, presence: true
  validates :name, uniqueness: { scope: :user_id }
  validates :visibility, presence: true
end
