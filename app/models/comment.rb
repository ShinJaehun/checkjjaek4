class Comment < ApplicationRecord
  belongs_to :jjaek
  belongs_to :user

  validates :content, presence: true, length: { maximum: 200 }
end
