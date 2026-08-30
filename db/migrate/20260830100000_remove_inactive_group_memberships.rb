class RemoveInactiveGroupMemberships < ActiveRecord::Migration[8.1]
  INACTIVE_MEMBERSHIP_STATUS = 3
  ACTIVE_GROUP_STATUS = 1

  def up
    invalid_admin_membership = select_value(<<~SQL.squish)
      SELECT group_memberships.id
      FROM group_memberships
      INNER JOIN groups ON groups.id = group_memberships.group_id
      WHERE group_memberships.status = #{INACTIVE_MEMBERSHIP_STATUS}
        AND groups.lifecycle_status = #{ACTIVE_GROUP_STATUS}
        AND groups.group_admin_id = group_memberships.user_id
      LIMIT 1
    SQL

    if invalid_admin_membership
      raise ActiveRecord::MigrationError,
            "Inactive membership #{invalid_admin_membership} belongs to the current admin of an active group"
    end

    execute <<~SQL.squish
      DELETE FROM group_memberships
      WHERE status = #{INACTIVE_MEMBERSHIP_STATUS}
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
