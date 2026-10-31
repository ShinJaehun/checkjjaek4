class AnonymizeRegistrationInvitationEmailsJob < ApplicationJob
  def perform
    RegistrationInvitations::AnonymizeDueEmails.new.call
  end
end
