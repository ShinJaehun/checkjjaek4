class BookFriendship < ApplicationRecord
  enum :status, { pending: 0, accepted: 1 }, default: :pending, validate: true

  belongs_to :requester, class_name: "User", inverse_of: :requested_book_friendships
  belongs_to :addressee, class_name: "User", inverse_of: :received_book_friendships

  validate :not_self
  validate :unique_pair, on: :create

  scope :accepted_only, -> { where(status: :accepted) }

  def self.between(first_user, second_user)
    return if first_user.blank? || second_user.blank?

    where(requester: first_user, addressee: second_user)
      .or(where(requester: second_user, addressee: first_user))
      .first
  end

  def self.connected_ids_for(user)
    accepted_only
      .where("requester_id = :id OR addressee_id = :id", id: user.id)
      .pluck(:requester_id, :addressee_id)
      .flatten
      .uniq
      .excluding(user.id)
  end

  private

  def unique_pair
    return if requester_id.blank? || addressee_id.blank?
    return unless self.class.between(requester, addressee)

    errors.add(:addressee_id, :taken)
  end

  def not_self
    return unless requester_id.present? && requester_id == addressee_id

    errors.add(:addressee_id, :invalid)
  end
end
