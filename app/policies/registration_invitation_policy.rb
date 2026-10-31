class RegistrationInvitationPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.global_admin? ? scope.all : scope.none
    end
  end

  def index?
    user&.global_admin?
  end

  def create?
    user&.global_admin?
  end

  def resend?
    user&.global_admin? && !record.anonymized_email? && record.consumed_at.nil? && record.canceled_at.nil?
  end

  def destroy?
    resend?
  end
end
