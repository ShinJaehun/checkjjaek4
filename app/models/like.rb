class Like < ApplicationRecord
  belongs_to :user
  belongs_to :jjaek

  validates :jjaek_id, uniqueness: { scope: :user_id }
end
