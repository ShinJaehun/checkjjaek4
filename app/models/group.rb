class Group < ApplicationRecord
  USER_CREATABLE_TYPES = %w[public_group approval_group private_group].freeze

  enum :group_type,
       { public_group: 0, approval_group: 1, private_group: 2 },
       default: :public_group,
       validate: true

  belongs_to :owner, class_name: "User", inverse_of: :owned_groups
  has_many :group_memberships, dependent: :destroy
  has_many :active_group_memberships, -> { active }, class_name: "GroupMembership"
  has_many :members, through: :active_group_memberships, source: :user
  has_many :jjaeks, dependent: :restrict_with_error

  validates :name, presence: true

  after_create :create_owner_membership!

  def active_member?(user)
    user.present? && group_memberships.active.exists?(user: user)
  end

  def owner?(user)
    user.present? && owner_id == user.id
  end

  private

  def create_owner_membership!
    group_memberships.create!(user: owner, status: :active)
  end
end
