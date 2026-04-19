class Post < ApplicationRecord
  enum :visibility, { public_feed: 0 }, default: :public_feed, validate: true

  belongs_to :user
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy

  validates :content, presence: true, length: { maximum: 280 }

  scope :recent, -> { order(created_at: :desc) }
end
