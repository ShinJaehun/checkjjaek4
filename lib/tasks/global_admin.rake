require "etc"
require "socket"

module GlobalAdminRoleTask
  def self.run(action)
    user_id = ENV["USER_ID"].to_s
    expected_email = ENV["EMAIL"].to_s.strip.downcase
    abort "USER_ID and EMAIL are required" unless user_id.match?(/\A[1-9]\d*\z/) && expected_email.present?

    user = User.find_by(id: user_id)
    abort "User not found or email does not match" unless user && user.email == expected_email

    puts "Target: #{user.id} #{user.email}"
    puts "Account: #{user.moderation_status}, global_admin: #{user.global_admin?}"
    puts "Action: #{action}"
    print "Reason: "
    reason = $stdin.gets&.strip
    abort "Reason is required" if reason.blank?

    print "Type #{action.upcase} #{user.id} to confirm: "
    abort "Confirmation did not match" unless $stdin.gets&.strip == "#{action.upcase} #{user.id}"

    operator_uid = Process.uid
    operator_account = begin
      Etc.getpwuid(operator_uid).name
    rescue ArgumentError
      "uid:#{operator_uid}"
    end
    server_hostname = Socket.gethostname
    execution_id = SecureRandom.uuid

    changed_user = GlobalAdminRoles::Change.new(
      user_id: user.id,
      action:,
      reason:,
      operator_uid:,
      operator_account:,
      server_hostname:,
      execution_id:
    ).call!

    Rails.logger.info("global_admin_role_change execution_id=#{execution_id} action=#{action} user_id=#{changed_user.id} operator_uid=#{operator_uid} server=#{server_hostname}")
    puts "Completed: global_admin=#{changed_user.global_admin?}, execution_id=#{execution_id}"
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique,
         GlobalAdminRoles::Change::Error => error
    abort "Role change failed: #{error.class.name}"
  end
end

namespace :global_admin do
  desc "Grant global admin to an existing active user"
  task grant: :environment do
    GlobalAdminRoleTask.run("grant")
  end

  desc "Revoke global admin while retaining an active global admin"
  task revoke: :environment do
    GlobalAdminRoleTask.run("revoke")
  end
end
