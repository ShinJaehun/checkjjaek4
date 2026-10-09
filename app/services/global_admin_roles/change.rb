module GlobalAdminRoles
  class Change
    class Error < StandardError; end
    class InvalidState < Error; end
    class LastActiveAdmin < Error; end

    # All role changes use one transaction lock so the active-admin count cannot race.
    ADVISORY_LOCK_KEY = 1_672_593_416_490_356_001

    def initialize(user_id:, action:, reason:, operator_uid:, operator_account:, server_hostname:, execution_id:)
      @user_id = user_id
      @action = action.to_s
      @reason = reason.to_s.strip
      @operator_uid = operator_uid
      @operator_account = operator_account
      @server_hostname = server_hostname
      @execution_id = execution_id
    end

    def call!
      raise InvalidState unless action.in?(%w[grant revoke]) && reason.present?

      User.transaction do
        User.connection.execute("SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK_KEY})")
        user = User.lock.find(user_id)
        before = user.global_admin?

        case action
        when "grant"
          raise InvalidState if before || user.withdrawn? || user.suspended? || !user.active_for_authentication?
        when "revoke"
          raise InvalidState unless before
          remaining_active_admins = active_admin_count
          remaining_active_admins -= 1 if user.moderation_status == :active && user.active_for_authentication?
          raise LastActiveAdmin if remaining_active_admins < 1
        end

        user.update!(global_admin: action == "grant")
        GlobalAdminRoleChange.create!(
          user:,
          action:,
          global_admin_before: before,
          global_admin_after: user.global_admin?,
          reason:,
          operator_uid:,
          operator_account:,
          server_hostname:,
          execution_id:
        )
        user
      end
    end

    private

    attr_reader :user_id, :action, :reason, :operator_uid, :operator_account, :server_hostname, :execution_id

    def active_admin_count
      User.where(global_admin: true, withdrawn_at: nil, suspended_at: nil).count
    end
  end
end
