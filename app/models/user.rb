class User < ApplicationRecord
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable

  normalizes :email, with: ->(email) { email.strip.downcase }

  has_many :bookshelf_entries, dependent: :destroy
  has_many :books, through: :bookshelf_entries
  has_many :jjaeks, dependent: :destroy
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

  has_many :requested_book_friendships,
           class_name: "BookFriendship",
           foreign_key: :requester_id,
           inverse_of: :requester,
           dependent: :destroy
  has_many :received_book_friendships,
           class_name: "BookFriendship",
           foreign_key: :addressee_id,
           inverse_of: :addressee,
           dependent: :destroy

  validates :name, presence: true

  def follows?(other_user)
    followees.exists?(other_user.id)
  end

  def book_friendship_with(other_user)
    BookFriendship.between(self, other_user)
  end

  def book_friend?(other_user)
    book_friendship_with(other_user)&.accepted?
  end

  def incoming_book_friend_requests
    received_book_friendships.pending.includes(:requester)
  end
end
