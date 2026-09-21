class Comment < ApplicationRecord
  MODERATION_HIDE_REASONS = Jjaek::MODERATION_HIDE_REASONS

  belongs_to :jjaek
  belongs_to :user
  has_many :moderation_actions, as: :target

  validates :content, presence: true, length: { maximum: 200 }

  scope :visible, -> { where(hidden_at: nil) }

  def hidden?
    hidden_at.present?
  end

  def current_hide_action
    ModerationAction.current_hide_for(self)
  end
end
