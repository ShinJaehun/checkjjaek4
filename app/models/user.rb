class User < ApplicationRecord
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable

  normalizes :email, with: ->(email) { email.strip.downcase }

  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy

  has_many :active_follows,
           class_name: "Follow",
           foreign_key: :follower_id,
           inverse_of: :follower,
           dependent: :destroy
  has_many :followees, through: :active_follows, source: :followee

  has_many :passive_follows,
           class_name: "Follow",
           foreign_key: :followee_id,
           inverse_of: :followee,
           dependent: :destroy
  has_many :followers, through: :passive_follows, source: :follower

  validates :name, presence: true

  def follows?(other_user)
    followees.exists?(other_user.id)
  end

  def feed_posts
    Post.where(user_id: [ id ] + followee_ids).recent
  end
end
