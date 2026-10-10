class DiscoveryPolicy < ApplicationPolicy
  def show?
    user.present?
  end
end
