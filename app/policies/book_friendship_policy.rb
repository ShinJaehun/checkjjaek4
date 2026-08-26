class BookFriendshipPolicy < ApplicationPolicy
  def create?
    user.present? && user.active_account? && record.addressee&.active_account? &&
      record.requester_id == user.id && record.addressee_id != user.id
  end

  def accept?
    user.present? && record.addressee_id == user.id
  end

  def destroy?
    user.present? && [ record.requester_id, record.addressee_id ].include?(user.id)
  end
end
