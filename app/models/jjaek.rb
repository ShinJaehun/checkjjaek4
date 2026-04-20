class Jjaek < ApplicationRecord
  enum :visibility, { public_jjaek: 0, book_friends: 1, private_jjaek: 2 },
       default: :public_jjaek,
       validate: true

  belongs_to :user
  belongs_to :book
  belongs_to :quoted_jjaek, class_name: "Jjaek", optional: true

  has_many :requotes, class_name: "Jjaek", foreign_key: :quoted_jjaek_id, dependent: :nullify, inverse_of: :quoted_jjaek
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy

  validates :content, presence: true, length: { maximum: 2_000 }
  validate :quoted_jjaek_must_be_requotable
  validate :quoted_jjaek_visibility_must_not_expand

  scope :recent, -> { order(created_at: :desc) }

  def requote?
    quoted_jjaek_id.present?
  end

  private

  def quoted_jjaek_must_be_requotable
    return unless quoted_jjaek.present?
    return unless quoted_jjaek.private_jjaek?

    errors.add(:quoted_jjaek, :invalid)
  end

  def quoted_jjaek_visibility_must_not_expand
    return unless quoted_jjaek.present?
    return if visibility_rank >= quoted_jjaek.send(:visibility_rank)

    errors.add(:visibility, :inclusion)
  end

  def visibility_rank
    case visibility
    when "public_jjaek" then 0
    when "book_friends" then 1
    else 2
    end
  end
end
