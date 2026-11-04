class JjaekRecommendation < ApplicationRecord
  belongs_to :jjaek, inverse_of: :jjaek_recommendations
  belongs_to :book

  validates :book_id, uniqueness: { scope: :jjaek_id }, if: -> { book_id.present? }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       uniqueness: { scope: :jjaek_id }
  validate :jjaek_must_be_recommendation

  private

  def jjaek_must_be_recommendation
    errors.add(:jjaek, :invalid) unless jjaek&.recommendation?
  end
end
