class Notification < ApplicationRecord
  enum :action, {
    book_friendship_requested: 0,
    profile_jjaek_created: 1,
    comment_created: 2,
    requote_created: 3
  }, validate: true

  belongs_to :recipient, class_name: "User", inverse_of: :received_notifications
  belongs_to :actor, class_name: "User", inverse_of: :sent_notifications
  belongs_to :notifiable, polymorphic: true

  validates :action, presence: true
  validates :notifiable_id, uniqueness: {
    scope: %i[recipient_id actor_id action notifiable_type],
    message: :taken
  }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def self.notify_book_friendship_requested(book_friendship)
    notify_once(
      recipient: book_friendship.addressee,
      actor: book_friendship.requester,
      action: :book_friendship_requested,
      notifiable: book_friendship
    )
  end

  def self.notify_profile_jjaek_created(jjaek)
    return unless jjaek.target_user.present?
    return unless JjaekPolicy.new(jjaek.target_user, jjaek).show?

    notify_once(
      recipient: jjaek.target_user,
      actor: jjaek.user,
      action: :profile_jjaek_created,
      notifiable: jjaek
    )
  end

  def self.notify_comment_created(comment)
    notify_once(
      recipient: comment.jjaek.user,
      actor: comment.user,
      action: :comment_created,
      notifiable: comment
    )
  end

  def self.notify_requote_created(requote)
    return unless requote.quoted_jjaek.present?

    recipient = requote.quoted_jjaek.user
    return unless JjaekPolicy.new(recipient, requote).show?

    notify_once(
      recipient:,
      actor: requote.user,
      action: :requote_created,
      notifiable: requote
    )
  end

  def self.notify_once(recipient:, actor:, action:, notifiable:)
    return if recipient == actor

    find_or_create_by!(
      recipient:,
      actor:,
      action:,
      notifiable:
    )
  end

  def unread?
    read_at.nil?
  end
end
