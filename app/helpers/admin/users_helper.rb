module Admin
  module UsersHelper
    include ::UsersHelper

    USER_STATUS_FILTERS = %w[active suspended withdrawn].freeze
    USER_ROLE_FILTERS = %w[global_admin group_admin regular].freeze

    def admin_user_status_label(status)
      t("admin.users.statuses.#{status}")
    end

    def admin_user_status_badge_classes(status)
      case status.to_s
      when "active" then "bg-emerald-100 text-emerald-800"
      when "suspended" then "bg-red-100 text-red-800"
      else "bg-stone-200 text-stone-700"
      end
    end

    def admin_user_status_filter_options
      USER_STATUS_FILTERS.map { |status| [admin_user_status_label(status), status] }
    end

    def admin_user_role_keys(user, has_administered_groups:)
      roles = []
      roles << "global_admin" if user.global_admin?
      roles << "group_admin" if has_administered_groups
      roles.presence || ["regular"]
    end

    def admin_user_role_filter_options
      USER_ROLE_FILTERS.map { |role| [user_role_label(role), role] }
    end
  end
end
