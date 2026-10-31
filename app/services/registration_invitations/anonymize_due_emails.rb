module RegistrationInvitations
  class AnonymizeDueEmails
    RETENTION_PERIOD = 30.days
    BATCH_SIZE = 500

    def call
      cutoff = RETENTION_PERIOD.ago
      due_invitations(cutoff).find_each(batch_size: BATCH_SIZE) do |invitation|
        anonymize_if_due(invitation, cutoff)
      end
    end

    private

    def due_invitations(cutoff)
      RegistrationInvitation.with_original_email.where(consumed_at: nil)
        .where("(canceled_at IS NULL AND expires_at <= :cutoff) OR canceled_at <= :cutoff", cutoff: cutoff)
    end

    def due?(invitation, cutoff)
      return false if invitation.consumed_at? || invitation.anonymized_email?

      (invitation.canceled_at || invitation.expires_at) <= cutoff
    end

    def anonymize_if_due(invitation, cutoff)
      invitation.with_lock do
        invitation.update!(email: invitation.anonymized_email) if due?(invitation, cutoff)
      end
    end
  end
end
