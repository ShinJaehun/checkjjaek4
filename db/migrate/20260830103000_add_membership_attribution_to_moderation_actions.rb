class AddMembershipAttributionToModerationActions < ActiveRecord::Migration[8.1]
  def change
    add_column :moderation_actions, :membership_group_id, :bigint
    add_column :moderation_actions, :membership_user_id, :bigint
    add_index :moderation_actions, [ :membership_group_id, :created_at, :id ],
              name: "index_moderation_actions_on_membership_group_and_time"

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE moderation_actions
          SET membership_group_id = group_memberships.group_id,
              membership_user_id = group_memberships.user_id
          FROM group_memberships
          WHERE moderation_actions.target_type = 'GroupMembership'
            AND moderation_actions.target_id = group_memberships.id
        SQL
      end
    end
  end
end
